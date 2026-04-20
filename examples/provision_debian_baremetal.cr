require "../src/scaleway_api"

# Exemple end-to-end : installation Debian sur un nouveau serveur Elastic
# Metal Scaleway (création + install couplés), suivi par événements, puis
# pose du DNS inverse.
#
# Variables d'environnement requises :
#   SCW_SECRET_KEY            — clé IAM Scaleway (console → IAM → API keys).
#   SCW_DEFAULT_PROJECT_ID    — UUID du projet Scaleway qui recevra le serveur.
#
# Variables optionnelles :
#   SCW_ZONE                  — fr-par-2 par défaut.
#   TARGET_HOSTNAME           — web01.aloli.fr par défaut.
#   SSH_PUBLIC_KEY            — clé publique à uploader avant l'install.
#
# Usage :
#   crystal run examples/provision_debian_baremetal.cr
#
# Par sécurité, ce fichier ne *déclenche* pas la commande tant que
# SCW_CONFIRM=yes n'est pas positionnée : une création Elastic Metal est
# facturée.

SECRET_KEY     = ENV["SCW_SECRET_KEY"]? || ""
PROJECT_ID     = ENV["SCW_DEFAULT_PROJECT_ID"]? || ""
ZONE           = ENV["SCW_ZONE"]? || "fr-par-2"
HOSTNAME       = ENV["TARGET_HOSTNAME"]? || "web01.aloli.fr"
SSH_PUBLIC_KEY = ENV["SSH_PUBLIC_KEY"]? || ""
CONFIRM        = ENV["SCW_CONFIRM"]? == "yes"

if SECRET_KEY.empty? || PROJECT_ID.empty?
  STDERR.puts "Credentials Scaleway manquants. Positionnez SCW_SECRET_KEY et " \
              "SCW_DEFAULT_PROJECT_ID."
  exit 2
end

client = ScalewayApi::Client.new(
  secret_key: SECRET_KEY,
  default_project_id: PROJECT_ID,
  default_zone: ZONE,
)

# 1. S'assurer qu'une clé SSH existe sur le projet ; en créer une depuis
#    SSH_PUBLIC_KEY si la liste est vide.
puts "Clés SSH déclarées sur le projet :"
keys = client.ssh_keys.list
keys.each { |k| puts "  - #{k.name} (#{k.id})" }

if keys.empty?
  if SSH_PUBLIC_KEY.empty?
    STDERR.puts "Aucune clé SSH déclarée et SSH_PUBLIC_KEY non définie."
    exit 3
  end
  puts "Création d'une clé SSH 'provisioner' à partir de SSH_PUBLIC_KEY..."
  new_key = client.ssh_keys.create(name: "provisioner", public_key: SSH_PUBLIC_KEY)
  keys = [new_key]
end

# 2. Choisir une offre disponible.
offers = client.baremetal.offers.list
available = offers.find { |o| o.stock == "available" }
unless available
  STDERR.puts "Aucune offre Elastic Metal disponible dans la zone #{ZONE}."
  offers.first(5).each { |o| STDERR.puts "  - #{o.name} (#{o.stock})" }
  exit 4
end
puts "Offre retenue : #{available.name} (#{available.id})"

# 3. Trouver un OS Debian.
os = client.baremetal.oses.find_by_name_prefix("debian")
unless os
  STDERR.puts "Aucun OS Debian proposé dans cette zone."
  exit 5
end
puts "OS retenu : #{os.name} (#{os.id})"

if !CONFIRM
  puts
  puts "SCW_CONFIRM=yes non défini → arrêt avant la création (facturée)."
  puts "Relancez avec SCW_CONFIRM=yes pour lancer l'installation."
  exit 0
end

# 4. Lancer la création + installation en un seul POST.
install = ScalewayApi::Endpoints::Baremetal::Install.new(
  os_id: os.id,
  hostname: HOSTNAME,
  ssh_key_ids: keys.map(&.id),
)

puts "Création du serveur #{HOSTNAME} sur #{available.name}..."
server = client.baremetal.servers.create(
  offer_id: available.id,
  install: install,
  name: HOSTNAME,
  reverse: HOSTNAME,
)
puts "Serveur #{server.id} créé (état #{server.status})."

# 5. Poll toutes les 30 s sur les événements.
loop do
  sleep 30.seconds
  events = client.baremetal.servers.events(server_id: server.id)
  latest = events.find { |e| e.action == "install_server" }
  if latest
    puts "[#{Time.utc}] install_server → #{latest.status}"
    break if latest.success? || latest.failed?
  end
  refreshed = client.baremetal.servers.get(server.id)
  break if refreshed.ready? || refreshed.failed?
end

# 6. État final.
final = client.baremetal.servers.get(server.id)
if final.ready?
  puts "Installation terminée. Serveur prêt."
  final.ips.each { |ip| puts "  IP #{ip.version || "?"} : #{ip.address} (reverse #{ip.reverse || "?"})" }
else
  STDERR.puts "État final : #{final.status}"
  exit 6
end
