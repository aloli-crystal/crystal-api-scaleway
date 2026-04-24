require "json"

module ScalewayApi
  module Endpoints
    module Baremetal
      # Paramètres d'installation d'un serveur Elastic Metal.
      #
      # `Install` est passé au `servers.create` (pour coupler
      # création + installation en un appel) ou à `servers.install`
      # (pour réinstaller un serveur existant).
      #
      # * `os_id`                : UUID de l'OS (cf. `client.baremetal.oses`).
      # * `hostname`             : nom de machine posé pendant l'install.
      # * `ssh_key_ids`          : UUIDs des clés autorisées (cf.
      #                            `client.ssh_keys`). Doit en contenir
      #                            au moins une, sinon pas d'accès.
      # * `user`                 : utilisateur à créer (optionnel ; par
      #                            défaut, dépend de l'OS — `root` ou
      #                            `ubuntu` selon).
      # * `password`             : mot de passe de `user`. Déconseillé
      #                            (exposé via l'API Scaleway). Préférer
      #                            la connexion par clé SSH.
      # * `service_user`         : nom d'un second utilisateur (optionnel).
      # * `service_password`     : mot de passe du `service_user`.
      #
      # Le champ `cloud_init` existe côté Scaleway mais n'est pas exposé
      # dans cette v0.1 : l'écosystème Aloli pose sa propre post-install
      # via crystal-beryl après le premier boot.
      struct Install
        getter os_id : String
        getter hostname : String
        getter ssh_key_ids : Array(String)
        getter user : String?
        getter password : String?
        getter service_user : String?
        getter service_password : String?

        def initialize(
          @os_id : String,
          @hostname : String,
          @ssh_key_ids : Array(String),
          @user : String? = nil,
          @password : String? = nil,
          @service_user : String? = nil,
          @service_password : String? = nil,
        )
        end

        # Sérialise l'install en objet JSON, en omettant les champs nil
        # (important : Scaleway rejette `"user": null` avec
        # `invalid_argument`).
        def to_json_object : String
          JSON.build do |json|
            json.object do
              json.field "os_id", @os_id
              json.field "hostname", @hostname
              json.field "ssh_key_ids" do
                json.array do
                  @ssh_key_ids.each { |id| json.string id }
                end
              end
              json.field "user", @user if @user
              json.field "password", @password if @password
              json.field "service_user", @service_user if @service_user
              json.field "service_password", @service_password if @service_password
            end
          end
        end
      end

      # Mode de redémarrage accepté par `Servers#reboot`.
      #
      # * `Normal` (`"normal"`) — redémarrage classique vers l'OS installé.
      # * `Rescue` (`"rescue"`) — bascule en mode rescue Scaleway
      #   (image Ubuntu en RAM, utilisateur `rescue`). Le rescue dure
      #   environ 1 h, puis Scaleway reboote automatiquement sur l'OS
      #   installé.
      #
      #   ATTENTION sur l'injection des clés SSH : d'après la doc
      #   officielle (https://www.scaleway.com/en/docs/bare-metal/elastic-metal/how-to/use-rescue-mode/),
      #   l'authentification rescue utilise « the SSH keys **registered
      #   for your Elastic Metal server** » — c'est-à-dire la liste
      #   `install.ssh_key_ids` posée lors de l'install initiale
      #   (`Servers#create` ou `Servers#install`). Aucun endpoint
      #   documenté ne permet de rafraîchir cette liste sans refaire
      #   un `install`.
      #
      #   Conséquence pratique : ajouter une clé au projet
      #   (https://console.scaleway.com/project/ssh-keys) APRÈS la
      #   création du serveur **ne propage pas la clé** dans le rescue.
      #   Le prochain `reboot(Rescue)` lira la même liste figée
      #   qu'avant. Pour resynchroniser, il faut appeler
      #   `Servers#install` avec la nouvelle liste `ssh_key_ids` (ce
      #   qui réinstalle l'OS sur le disque).
      enum BootType
        Normal
        Rescue

        # Valeur attendue par l'API Scaleway dans le corps JSON
        # (`"normal"` ou `"rescue"`, en minuscules).
        def to_api : String
          case self
          in Normal then "normal"
          in Rescue then "rescue"
          end
        end
      end

      # Endpoints `/baremetal/v1/zones/{zone}/servers`.
      #
      # Contrairement à OVH (où il faut commander le serveur, puis attendre
      # la livraison, puis lancer une réinstallation), Scaleway combine
      # *création* et *installation* dans un seul appel POST — l'objet
      # `install` est embarqué dans le corps de création.
      #
      # Un serveur existant peut ensuite être réinstallé via
      # `POST /servers/{id}/install`. Le suivi passe par les événements
      # (`GET /servers/{id}/events`).
      class Servers
        def initialize(@client : ScalewayApi::Client)
        end

        # Liste les serveurs d'une zone (éventuellement filtrée par
        # projet).
        #
        # `GET /baremetal/v1/zones/{zone}/servers` → `{"servers": [...]}`.
        def list(
          zone : String? = nil,
          project_id : String? = nil,
          page : Int32? = nil,
          page_size : Int32? = nil,
        ) : Array(Server)
          z = @client.resolve_zone(zone)
          query = Hash(String, String).new
          query["project_id"] = project_id if project_id
          query["page"] = page.to_s if page
          query["page_size"] = page_size.to_s if page_size

          result = @client.call(
            "GET",
            "/baremetal/v1/zones/#{z}/servers",
            query: query.empty? ? nil : query,
          )
          arr = result.try(&.["servers"]?).try(&.as_a?) || [] of JSON::Any
          arr.map { |payload| Server.from_any(payload) }
        end

        # Détail d'un serveur par UUID.
        #
        # `GET /baremetal/v1/zones/{zone}/servers/{server_id}`.
        def get(server_id : String, zone : String? = nil) : Server
          z = @client.resolve_zone(zone)
          result = @client.call(
            "GET",
            "/baremetal/v1/zones/#{z}/servers/#{server_id}",
          )
          Server.from_any(result.not_nil!)
        end

        # Balaye l'ensemble des zones Scaleway connues
        # (`ScalewayApi::ZONES`) à la recherche d'un serveur Elastic
        # Metal par UUID. Utile quand l'appelant connaît l'UUID mais
        # pas la zone (outillage multi-zones, script d'import, UX
        # path-like).
        #
        # Retourne le premier `Server` trouvé (l'UUID est unique côté
        # Scaleway, donc il ne peut y en avoir qu'un). Retourne `nil`
        # si aucune zone ne reconnaît l'UUID.
        #
        # Les zones qui répondent 501 `unknown_service` (pas encore
        # activées pour Elastic Metal) sont silencieusement ignorées.
        # Les autres `ApiError` sont relayées à l'appelant.
        #
        # La zone d'appartenance est accessible ensuite via
        # `server.zone`.
        def find_any_zone(server_id : String) : Server?
          ScalewayApi::ZONES.each do |zone|
            begin
              return get(server_id, zone: zone)
            rescue ScalewayApi::NotFound
              next
            rescue ex : ScalewayApi::ApiError
              next if ex.http_status == 501
              raise ex
            end
          end
          nil
        end

        # Crée un serveur *et* lance son installation.
        #
        # `POST /baremetal/v1/zones/{zone}/servers` avec `offer_id`,
        # `project_id`, `install` et — optionnellement — `name`,
        # `description`, `tags`, `reverse` (DNS inverse posé sur l'IP
        # principale).
        def create(
          offer_id : String,
          install : Install,
          zone : String? = nil,
          project_id : String? = nil,
          name : String? = nil,
          description : String? = nil,
          tags : Array(String)? = nil,
          reverse : String? = nil,
        ) : Server
          z = @client.resolve_zone(zone)
          pid = @client.resolve_project_id(project_id)

          # Construction à la main pour maîtriser l'ordre et omettre
          # proprement les champs nil.
          body = JSON.build do |json|
            json.object do
              json.field "offer_id", offer_id
              json.field "project_id", pid
              json.field "name", name if name
              json.field "description", description if description
              if tags
                json.field "tags" do
                  json.array do
                    tags.each { |t| json.string t }
                  end
                end
              end
              json.field "reverse", reverse if reverse
              json.field "install" do
                json.raw install.to_json_object
              end
            end
          end

          result = @client.call(
            "POST",
            "/baremetal/v1/zones/#{z}/servers",
            body: body,
          )
          Server.from_any(result.not_nil!)
        end

        # (Ré)installe un serveur existant.
        #
        # `POST /baremetal/v1/zones/{zone}/servers/{server_id}/install`.
        def install(
          server_id : String,
          install : Install,
          zone : String? = nil,
        ) : Server
          z = @client.resolve_zone(zone)
          result = @client.call(
            "POST",
            "/baremetal/v1/zones/#{z}/servers/#{server_id}/install",
            body: install.to_json_object,
          )
          Server.from_any(result.not_nil!)
        end

        # Redémarre un serveur, éventuellement en mode rescue.
        #
        # `POST /baremetal/v1/zones/{zone}/servers/{server_id}/reboot` avec
        # `{"boot_type": "normal"}` ou `{"boot_type": "rescue"}`.
        #
        # En mode `Rescue`, Scaleway ré-injecte automatiquement les clés
        # SSH posées à la création du serveur (champ `ssh_key_ids` de
        # l'`install`) dans l'environnement rescue. L'IP de management
        # reste la même (pas de NAT spécifique). Le rescue dure environ
        # 1 h avant que Scaleway ne reboote automatiquement sur l'OS
        # installé.
        #
        # Erreurs usuelles :
        #
        # * HTTP 403 (`permissions_denied`) — la clé IAM n'a pas le droit
        #   `ElasticMetalFullAccess`.
        # * HTTP 409 — le serveur n'est pas dans un état compatible
        #   (`installing`, `delivering`, `deleting`…). Attendre `ready`
        #   ou `stopped` avant de relancer.
        #
        # Retourne l'objet `Server` mis à jour (status typiquement
        # `stopping` puis `starting`, puis `ready` / `rescue` selon le
        # mode).
        def reboot(
          server_id : String,
          boot_type : BootType = BootType::Normal,
          zone : String? = nil,
        ) : Server
          z = @client.resolve_zone(zone)
          body = JSON.build do |json|
            json.object do
              json.field "boot_type", boot_type.to_api
            end
          end
          result = @client.call(
            "POST",
            "/baremetal/v1/zones/#{z}/servers/#{server_id}/reboot",
            body: body,
          )
          Server.from_any(result.not_nil!)
        end

        # Met à jour un serveur (notamment le DNS inverse, via `reverse`).
        #
        # `PATCH /baremetal/v1/zones/{zone}/servers/{server_id}`.
        #
        # Le reverse est *normalisé* par Scaleway : passez `"web01.aloli.fr"`
        # (sans point final) ou `"web01.aloli.fr."` indifféremment.
        def update(
          server_id : String,
          zone : String? = nil,
          name : String? = nil,
          description : String? = nil,
          tags : Array(String)? = nil,
          reverse : String? = nil,
        ) : Server
          z = @client.resolve_zone(zone)
          body = JSON.build do |json|
            json.object do
              json.field "name", name if name
              json.field "description", description if description
              if tags
                json.field "tags" do
                  json.array do
                    tags.each { |t| json.string t }
                  end
                end
              end
              json.field "reverse", reverse if reverse
            end
          end
          result = @client.call(
            "PATCH",
            "/baremetal/v1/zones/#{z}/servers/#{server_id}",
            body: body,
          )
          Server.from_any(result.not_nil!)
        end

        # Supprime un serveur.
        #
        # `DELETE /baremetal/v1/zones/{zone}/servers/{server_id}`.
        def delete(server_id : String, zone : String? = nil) : Nil
          z = @client.resolve_zone(zone)
          @client.call(
            "DELETE",
            "/baremetal/v1/zones/#{z}/servers/#{server_id}",
          )
        end

        # Liste les événements d'un serveur (utilisé pour suivre
        # l'installation).
        #
        # `GET /baremetal/v1/zones/{zone}/servers/{server_id}/events`.
        def events(
          server_id : String,
          zone : String? = nil,
          page : Int32? = nil,
          page_size : Int32? = nil,
        ) : Array(Event)
          z = @client.resolve_zone(zone)
          query = Hash(String, String).new
          query["page"] = page.to_s if page
          query["page_size"] = page_size.to_s if page_size

          result = @client.call(
            "GET",
            "/baremetal/v1/zones/#{z}/servers/#{server_id}/events",
            query: query.empty? ? nil : query,
          )
          arr = result.try(&.["events"]?).try(&.as_a?) || [] of JSON::Any
          arr.map { |payload| Event.from_any(payload) }
        end
      end

      # Représente une adresse IP attachée à un serveur Elastic Metal.
      struct ServerIp
        getter id : String
        getter address : String
        getter reverse : String?
        getter version : String?

        def initialize(
          @id : String,
          @address : String,
          @reverse : String? = nil,
          @version : String? = nil,
        )
        end

        def self.from_any(payload : JSON::Any) : ServerIp
          new(
            id: payload["id"].as_s,
            address: payload["address"].as_s,
            reverse: payload["reverse"]?.try(&.as_s?),
            version: payload["version"]?.try(&.as_s?),
          )
        end
      end

      # Serveur Elastic Metal.
      #
      # Les statuts Scaleway :
      #
      # * `unknown`         — état inconnu (réponse transitoire).
      # * `delivering`      — livraison du matériel.
      # * `ready`           — prêt mais pas installé.
      # * `stopping` / `stopped` / `starting` — cycles power.
      # * `installing`      — OS en cours d'installation.
      # * `deleting`        — suppression en cours.
      # * `locked`          — verrouillé (support Scaleway).
      # * `out_of_stock`    — offre en rupture.
      # * `error`           — erreur persistante.
      struct Server
        getter id : String
        getter name : String?
        getter status : String
        getter hostname : String?
        getter offer_id : String?
        getter offer_name : String?
        getter project_id : String?
        getter zone : String?
        getter ips : Array(ServerIp)
        getter tags : Array(String)
        getter created_at : String?
        getter updated_at : String?
        getter raw : JSON::Any

        def initialize(
          @id : String,
          @status : String,
          @raw : JSON::Any,
          @name : String? = nil,
          @hostname : String? = nil,
          @offer_id : String? = nil,
          @offer_name : String? = nil,
          @project_id : String? = nil,
          @zone : String? = nil,
          @ips : Array(ServerIp) = [] of ServerIp,
          @tags : Array(String) = [] of String,
          @created_at : String? = nil,
          @updated_at : String? = nil,
        )
        end

        def self.from_any(payload : JSON::Any) : Server
          ips = payload["ips"]?.try(&.as_a?).try(&.map { |i| ServerIp.from_any(i) }) || [] of ServerIp
          tags = payload["tags"]?.try(&.as_a?).try(&.map(&.as_s)) || [] of String
          new(
            id: payload["id"].as_s,
            status: payload["status"].as_s,
            name: payload["name"]?.try(&.as_s?),
            hostname: payload["hostname"]?.try(&.as_s?),
            offer_id: payload["offer_id"]?.try(&.as_s?),
            offer_name: payload["offer_name"]?.try(&.as_s?),
            project_id: payload["project_id"]?.try(&.as_s?),
            zone: payload["zone"]?.try(&.as_s?),
            ips: ips,
            tags: tags,
            created_at: payload["created_at"]?.try(&.as_s?),
            updated_at: payload["updated_at"]?.try(&.as_s?),
            raw: payload,
          )
        end

        # Le serveur est-il installé et prêt à l'emploi (hors
        # transitions) ?
        def ready? : Bool
          @status == "ready"
        end

        # L'installation est-elle en cours ?
        def installing? : Bool
          @status == "installing"
        end

        # L'état est-il un échec terminal ?
        def failed? : Bool
          @status == "error"
        end
      end

      # Événement sur un serveur (installation, redémarrage, etc.).
      #
      # Un événement d'installation réussie ressemble à :
      #
      # ```json
      # {
      #   "id": "...",
      #   "action": "install_server",
      #   "status": "success",
      #   "updated_at": "2026-04-18T10:45:00Z"
      # }
      # ```
      #
      # Les statuts connus : `pending`, `running`, `success`, `error`.
      struct Event
        getter id : String
        getter action : String?
        getter status : String?
        getter created_at : String?
        getter updated_at : String?
        getter raw : JSON::Any

        def initialize(
          @id : String,
          @raw : JSON::Any,
          @action : String? = nil,
          @status : String? = nil,
          @created_at : String? = nil,
          @updated_at : String? = nil,
        )
        end

        def self.from_any(payload : JSON::Any) : Event
          new(
            id: payload["id"].as_s,
            action: payload["action"]?.try(&.as_s?),
            status: payload["status"]?.try(&.as_s?),
            created_at: payload["created_at"]?.try(&.as_s?),
            updated_at: payload["updated_at"]?.try(&.as_s?),
            raw: payload,
          )
        end

        def success? : Bool
          @status == "success"
        end

        def failed? : Bool
          @status == "error"
        end
      end

      # Regroupe les sous-endpoints Elastic Metal dans un unique namespace
      # invocable depuis le client : `client.baremetal.servers`,
      # `client.baremetal.offers`, `client.baremetal.oses`.
      class Namespace
        def initialize(@client : ScalewayApi::Client)
        end

        def servers : Servers
          @servers ||= Servers.new(@client)
        end

        def offers : Offers
          @offers ||= Offers.new(@client)
        end

        def oses : Oses
          @oses ||= Oses.new(@client)
        end

        @servers : Servers?
        @offers : Offers?
        @oses : Oses?
      end
    end
  end
end
