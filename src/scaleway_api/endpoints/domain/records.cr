require "json"

module ScalewayApi
  module Endpoints
    module Domain
      # Endpoints `/domain/v2beta1/dns-zones/{zone}/records`.
      #
      # Scaleway expose une API DNS en deux temps :
      # - GET liste les records d'une zone
      # - PATCH applique un *changeset* (add/set/delete) en une seule
      #   requête, atomique.
      #
      # Pour garder l'usage simple côté appelant (comme `OvhApi::Endpoints::Domains`),
      # on expose les opérations courantes en méthodes dédiées :
      # `list`, `ensure`, `set`, `delete`. Chacune construit le
      # changeset approprié et envoie un PATCH en interne.
      class Records
        def initialize(@client : ScalewayApi::Client)
        end

        # Liste les records d'une zone, optionnellement filtrés par
        # type (`A`, `AAAA`, `CNAME`, `MX`…) et/ou par nom court.
        #
        # `GET /domain/v2beta1/dns-zones/{zone}/records`.
        #
        # `name` est le nom court (`loulou` pour `loulou.aloli.net`), ou
        # `""` pour la racine de la zone.
        def list(
          zone : String,
          type : String? = nil,
          name : String? = nil,
        ) : Array(Record)
          query = {} of String => String
          query["type"] = type if type
          query["name"] = name if name
          result = @client.call(
            "GET",
            "/domain/v2beta1/dns-zones/#{zone}/records",
            query: query.empty? ? nil : query,
          )
          raw = result.try(&.["records"]?) || return [] of Record
          raw.as_a.map { |r| Record.from_any(r) }
        end

        # Applique un « set » sur un couple (name, type) : tous les
        # records existants avec ce name+type sont remplacés par les
        # `data` fournis (un par ligne de `values`).
        #
        # `PATCH /domain/v2beta1/dns-zones/{zone}/records` avec
        # `{changes: [{set: {id_fields: {name, type}, records: [{data, ttl}]}}]}`.
        #
        # Cas d'usage typique pour un CNAME de serveur :
        #   `set(zone: "aloli.net", type: "CNAME", name: "loulou",`
        #       `values: ["ns3156789.ip-51-83-6.eu."], ttl: 3600)`.
        def set(
          zone : String,
          type : String,
          name : String,
          values : Array(String),
          ttl : Int32 = 3600,
        ) : Nil
          body = build_changeset([
            {
              "set" => {
                "id_fields" => {"name" => name, "type" => type},
                "records"   => values.map { |v| {"name" => name, "type" => type, "data" => v, "ttl" => ttl} },
              },
            },
          ])
          @client.call(
            "PATCH",
            "/domain/v2beta1/dns-zones/#{zone}/records",
            body: body,
          )
        end

        # Supprime tous les records avec le (name, type) fourni.
        def delete(zone : String, type : String, name : String) : Nil
          body = build_changeset([
            {
              "delete" => {
                "id_fields" => {"name" => name, "type" => type},
              },
            },
          ])
          @client.call(
            "PATCH",
            "/domain/v2beta1/dns-zones/#{zone}/records",
            body: body,
          )
        end

        # Idempotent : s'assure qu'il existe exactement un record
        # (name, type) qui pointe vers `value`. Crée / met à jour /
        # laisse tel quel selon l'état actuel. Retourne les records
        # après opération (la liste résultante).
        #
        # Pattern identique à `OvhApi::Endpoints::Domains#ensure_record`
        # pour que beryl puisse traiter les deux providers pareillement.
        def ensure(
          zone : String,
          type : String,
          name : String,
          value : String,
          ttl : Int32 = 3600,
        ) : Array(Record)
          existing = list(zone, type: type, name: name)
          if existing.size == 1 && existing.first.data == value
            return existing
          end
          set(zone, type: type, name: name, values: [value], ttl: ttl)
          list(zone, type: type, name: name)
        end

        private def build_changeset(changes : Array) : String
          JSON.build do |json|
            json.object do
              json.field "changes" do
                json.array do
                  changes.each do |change|
                    json.raw(change.to_json)
                  end
                end
              end
              json.field "return_all_records", false
            end
          end
        end
      end

      # Namespace regroupant les endpoints Domain pour un accès
      # idiomatique `client.domain.records`. Permet d'ajouter d'autres
      # endpoints Domain (zones, contacts, registrar) sans casser l'API.
      class Namespace
        def initialize(@client : ScalewayApi::Client)
        end

        def records : Records
          @records ||= Records.new(@client)
        end

        @records : Records?
      end

      # Un enregistrement DNS dans une zone Scaleway.
      struct Record
        getter id : String
        getter name : String
        getter type : String
        getter data : String
        getter ttl : Int32
        getter priority : Int32

        def initialize(@id, @name, @type, @data, @ttl, @priority)
        end

        def self.from_any(payload : JSON::Any) : Record
          new(
            id: payload["id"]?.try(&.as_s?) || "",
            name: payload["name"]?.try(&.as_s?) || "",
            type: payload["type"].as_s,
            data: payload["data"].as_s,
            ttl: payload["ttl"]?.try(&.as_i?) || 0,
            priority: payload["priority"]?.try(&.as_i?) || 0,
          )
        end
      end
    end
  end
end
