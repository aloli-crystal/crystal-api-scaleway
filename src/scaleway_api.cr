require "./scaleway_api/version"
require "./scaleway_api/errors"
require "./scaleway_api/endpoints/ssh_keys"
require "./scaleway_api/endpoints/baremetal/offers"
require "./scaleway_api/endpoints/baremetal/oses"
require "./scaleway_api/endpoints/baremetal/servers"
require "./scaleway_api/client"

# ScalewayApi — client Crystal pur (stdlib uniquement) pour l'API
# Scaleway REST v1.
#
# Couvre le strict nécessaire au provisioning Elastic Metal :
#
# * `client.ssh_keys`        — lister / créer / supprimer les clés SSH IAM
#                              du projet.
# * `client.baremetal.offers`  — catalogue Elastic Metal (EM-A115X-SSD, etc.).
# * `client.baremetal.oses`    — templates d'OS (Debian 13, Ubuntu 24.04…).
# * `client.baremetal.servers` — création + installation en un appel,
#                                réinstallation, mise à jour (reverse),
#                                suivi par événements.
#
# ```
# require "scaleway-api"
#
# client = ScalewayApi::Client.new(
#   secret_key: ENV["SCW_SECRET_KEY"],
#   default_project_id: ENV["SCW_DEFAULT_PROJECT_ID"],
#   default_zone: "fr-par-2",
# )
#
# key = client.ssh_keys.create(name: "laptop", public_key: "ssh-ed25519 AAAA...")
# os = client.baremetal.oses.find_by_name_prefix("debian").not_nil!
# offer = client.baremetal.offers.list.first
#
# server = client.baremetal.servers.create(
#   offer_id: offer.id,
#   install: ScalewayApi::Endpoints::Baremetal::Install.new(
#     os_id: os.id,
#     hostname: "web01.aloli.fr",
#     ssh_key_ids: [key.id],
#   ),
#   reverse: "web01.aloli.fr",
# )
#
# loop do
#   events = client.baremetal.servers.events(server_id: server.id)
#   break if events.any? { |e| e.action == "install_server" && e.success? }
#   sleep 30.seconds
# end
# ```
module ScalewayApi
end
