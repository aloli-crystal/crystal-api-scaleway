require "json"

module ScalewayApi
  module Endpoints
    # Endpoints `/iam/v1alpha1/ssh-keys`.
    #
    # Les clés SSH Scaleway sont gérées par le service IAM, pas par le
    # service Elastic Metal. Elles sont portées par un *projet* (pas un
    # compte), et référencées par UUID (`ssh_key_id`) au moment de
    # l'installation d'un serveur.
    #
    # Scaleway paginé : `page` (défaut 1) et `page_size` (défaut 20,
    # max 100). Ce shard expose `list` sans pagination automatique ; si
    # vous gérez plus de 100 clés, itérez manuellement avec `page:`.
    class SshKeys
      def initialize(@client : ScalewayApi::Client)
      end

      # Liste les clés SSH du projet.
      #
      # `GET /iam/v1alpha1/ssh-keys?project_id={id}` → `{"ssh_keys": [...]}`.
      #
      # * `project_id` : laisse tomber sur `default_project_id` du client
      #                  si non précisé.
      # * `page` / `page_size` : pagination Scaleway (optionnel).
      def list(
        project_id : String? = nil,
        page : Int32? = nil,
        page_size : Int32? = nil,
      ) : Array(SshKey)
        query = Hash(String, String).new
        query["project_id"] = @client.resolve_project_id(project_id)
        query["page"] = page.to_s if page
        query["page_size"] = page_size.to_s if page_size

        result = @client.call("GET", "/iam/v1alpha1/ssh-keys", query: query)
        arr = result.try(&.["ssh_keys"]?).try(&.as_a?) || [] of JSON::Any
        arr.map { |payload| SshKey.from_any(payload) }
      end

      # Détail d'une clé par UUID.
      #
      # `GET /iam/v1alpha1/ssh-keys/{ssh_key_id}`.
      def get(ssh_key_id : String) : SshKey
        result = @client.call("GET", "/iam/v1alpha1/ssh-keys/#{ssh_key_id}")
        SshKey.from_any(result.not_nil!)
      end

      # Ajoute une clé au projet.
      #
      # `POST /iam/v1alpha1/ssh-keys` avec `{name, public_key, project_id}`.
      #
      # * `name`       : libre, sert d'étiquette humaine.
      # * `public_key` : valeur complète (`ssh-ed25519 AAAA... commentaire`).
      # * `project_id` : laisse tomber sur `default_project_id` si `nil`.
      #
      # Retourne la `SshKey` créée, avec son `id` attribué par Scaleway.
      def create(
        name : String,
        public_key : String,
        project_id : String? = nil,
      ) : SshKey
        body = {
          "name"       => name,
          "public_key" => public_key,
          "project_id" => @client.resolve_project_id(project_id),
        }
        result = @client.call("POST", "/iam/v1alpha1/ssh-keys", body: body)
        SshKey.from_any(result.not_nil!)
      end

      # Supprime une clé par UUID.
      #
      # `DELETE /iam/v1alpha1/ssh-keys/{ssh_key_id}`.
      def delete(ssh_key_id : String) : Nil
        @client.call("DELETE", "/iam/v1alpha1/ssh-keys/#{ssh_key_id}")
      end
    end

    # Détail d'une clé SSH Scaleway (IAM).
    struct SshKey
      getter id : String
      getter name : String
      getter public_key : String
      getter fingerprint : String?
      getter project_id : String?
      getter created_at : String?
      getter updated_at : String?

      def initialize(
        @id : String,
        @name : String,
        @public_key : String,
        @fingerprint : String? = nil,
        @project_id : String? = nil,
        @created_at : String? = nil,
        @updated_at : String? = nil,
      )
      end

      def self.from_any(payload : JSON::Any) : SshKey
        new(
          id: payload["id"].as_s,
          name: payload["name"].as_s,
          public_key: payload["public_key"].as_s,
          fingerprint: payload["fingerprint"]?.try(&.as_s?),
          project_id: payload["project_id"]?.try(&.as_s?),
          created_at: payload["created_at"]?.try(&.as_s?),
          updated_at: payload["updated_at"]?.try(&.as_s?),
        )
      end
    end
  end
end
