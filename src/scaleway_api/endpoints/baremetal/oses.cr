require "json"

module ScalewayApi
  module Endpoints
    module Baremetal
      # Endpoints `/baremetal/v1/zones/{zone}/os`.
      #
      # Un *OS* est un template d'installation proposé par Scaleway
      # (Debian 13, Ubuntu 24.04, Rocky 9, FreeBSD 14…). Son `id` (UUID)
      # est nécessaire pour déclencher une installation
      # (`servers.install(os_id:)` ou `servers.create(install:)`).
      class Oses
        def initialize(@client : ScalewayApi::Client)
        end

        # Liste les OS disponibles à l'installation sur une zone.
        #
        # `GET /baremetal/v1/zones/{zone}/os` → `{"os": [...]}`.
        def list(
          zone : String? = nil,
          page : Int32? = nil,
          page_size : Int32? = nil,
        ) : Array(Os)
          z = @client.resolve_zone(zone)
          query = Hash(String, String).new
          query["page"] = page.to_s if page
          query["page_size"] = page_size.to_s if page_size

          result = @client.call(
            "GET",
            "/baremetal/v1/zones/#{z}/os",
            query: query.empty? ? nil : query,
          )
          arr = result.try(&.["os"]?).try(&.as_a?) || [] of JSON::Any
          arr.map { |payload| Os.from_any(payload) }
        end

        # Détail d'un OS par UUID.
        #
        # `GET /baremetal/v1/zones/{zone}/os/{os_id}`.
        def get(os_id : String, zone : String? = nil) : Os
          z = @client.resolve_zone(zone)
          result = @client.call(
            "GET",
            "/baremetal/v1/zones/#{z}/os/#{os_id}",
          )
          Os.from_any(result.not_nil!)
        end

        # Helper : trouve le premier OS dont le nom commence par `prefix`
        # (ex. `"debian"`, `"ubuntu_24"`). `nil` si aucun ne matche.
        #
        # Utile pour résoudre `"debian-13"` → `os_id` sans dépendre d'une
        # position fixe dans la liste.
        def find_by_name_prefix(prefix : String, zone : String? = nil) : Os?
          list(zone: zone).find { |o| o.name.starts_with?(prefix) }
        end
      end

      # Template OS Elastic Metal.
      struct Os
        getter id : String
        getter name : String
        getter version : String?
        getter logo_url : String?
        getter raw : JSON::Any

        def initialize(
          @id : String,
          @name : String,
          @raw : JSON::Any,
          @version : String? = nil,
          @logo_url : String? = nil,
        )
        end

        def self.from_any(payload : JSON::Any) : Os
          new(
            id: payload["id"].as_s,
            name: payload["name"].as_s,
            version: payload["version"]?.try(&.as_s?),
            logo_url: payload["logo_url"]?.try(&.as_s?),
            raw: payload,
          )
        end
      end
    end
  end
end
