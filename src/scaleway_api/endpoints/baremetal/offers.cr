require "json"

module ScalewayApi
  module Endpoints
    module Baremetal
      # Endpoints `/baremetal/v1/zones/{zone}/offers`.
      #
      # Une *offer* est un modèle de serveur commercialisé par Scaleway
      # Elastic Metal (EM-A115X-SSD, EM-A210R-HDD, etc.). Son `id` (UUID)
      # est nécessaire pour créer un serveur (`servers.create(offer_id:)`).
      class Offers
        def initialize(@client : ScalewayApi::Client)
        end

        # Liste les offres disponibles dans une zone.
        #
        # `GET /baremetal/v1/zones/{zone}/offers` → `{"offers": [...]}`.
        #
        # Scaleway pagine : `page` (défaut 1), `page_size` (défaut 20,
        # max 100). Sans argument, ce shard renvoie la première page
        # brute ; à l'appelant d'itérer s'il a besoin de plus.
        def list(
          zone : String? = nil,
          page : Int32? = nil,
          page_size : Int32? = nil,
        ) : Array(Offer)
          z = @client.resolve_zone(zone)
          query = Hash(String, String).new
          query["page"] = page.to_s if page
          query["page_size"] = page_size.to_s if page_size

          result = @client.call(
            "GET",
            "/baremetal/v1/zones/#{z}/offers",
            query: query.empty? ? nil : query,
          )
          arr = result.try(&.["offers"]?).try(&.as_a?) || [] of JSON::Any
          arr.map { |payload| Offer.from_any(payload) }
        end

        # Détail d'une offre par UUID.
        #
        # `GET /baremetal/v1/zones/{zone}/offers/{offer_id}`.
        def get(offer_id : String, zone : String? = nil) : Offer
          z = @client.resolve_zone(zone)
          result = @client.call(
            "GET",
            "/baremetal/v1/zones/#{z}/offers/#{offer_id}",
          )
          Offer.from_any(result.not_nil!)
        end
      end

      # Modèle d'offre Elastic Metal.
      #
      # Les champs matériels (`cpus`, `memories`, `disks`) sont exposés en
      # `JSON::Any` : Scaleway les structure en tableau de sous-objets
      # avec beaucoup de détails techniques (fréquence, modèle de disque,
      # ECC…), qu'il serait coûteux de refléter intégralement dans des
      # structs Crystal. Les utilisateurs qui ont besoin du détail
      # picoreront `raw`.
      struct Offer
        getter id : String
        getter name : String
        getter stock : String?
        getter bandwidth : Int64?
        getter commercial_range : String?
        getter price_per_hour : JSON::Any?
        getter price_per_month : JSON::Any?
        getter raw : JSON::Any

        def initialize(
          @id : String,
          @name : String,
          @raw : JSON::Any,
          @stock : String? = nil,
          @bandwidth : Int64? = nil,
          @commercial_range : String? = nil,
          @price_per_hour : JSON::Any? = nil,
          @price_per_month : JSON::Any? = nil,
        )
        end

        def self.from_any(payload : JSON::Any) : Offer
          new(
            id: payload["id"].as_s,
            name: payload["name"].as_s,
            stock: payload["stock"]?.try(&.as_s?),
            bandwidth: payload["bandwidth"]?.try(&.as_i64?),
            commercial_range: payload["commercial_range"]?.try(&.as_s?),
            price_per_hour: payload["price_per_hour"]?,
            price_per_month: payload["price_per_month"]?,
            raw: payload,
          )
        end
      end
    end
  end
end
