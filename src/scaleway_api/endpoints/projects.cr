require "json"

module ScalewayApi
  module Endpoints
    # Endpoints `/account/v3/projects` — gestion des projets Scaleway.
    #
    # Un *projet* Scaleway est le sous-conteneur de ressources sous une
    # *organisation*. À la création du compte, un projet `default` est
    # créé automatiquement avec l'UUID identique à celui de l'organisation
    # (constaté terrain 25 avril 2026).
    #
    # Le `project_id` est requis par tous les endpoints qui listent ou
    # créent des ressources (servers, ssh_keys, IP…). Cette section
    # permet de le découvrir automatiquement à partir du `secret_key` +
    # `organization_id`, sans demander à l'opérateur d'aller fouiller la
    # console.
    class Projects
      def initialize(@client : ScalewayApi::Client)
      end

      # Liste les projets d'une organisation.
      #
      # `GET /account/v3/projects?organization_id={id}` →
      # `{ "total_count": N, "projects": [...] }`.
      #
      # `organization_id` est obligatoire côté API : sans le filtre, la
      # réponse est `null` (constaté terrain). On l'exige donc en
      # argument plutôt qu'en option.
      def list(
        organization_id : String,
        page : Int32? = nil,
        page_size : Int32? = nil,
      ) : Array(Project)
        query = {"organization_id" => organization_id}
        query["page"] = page.to_s if page
        query["page_size"] = page_size.to_s if page_size

        result = @client.call("GET", "/account/v3/projects", query: query)
        arr = result.try(&.["projects"]?).try(&.as_a?) || [] of JSON::Any
        arr.map { |payload| Project.from_any(payload) }
      end

      # Détail d'un projet par UUID.
      #
      # `GET /account/v3/projects/{project_id}`.
      def get(project_id : String) : Project
        result = @client.call("GET", "/account/v3/projects/#{project_id}")
        Project.from_any(result.not_nil!)
      end
    end

    # Représente un projet Scaleway.
    struct Project
      getter id : String
      getter name : String
      getter organization_id : String?
      getter description : String?
      getter created_at : String?
      getter updated_at : String?

      def initialize(
        @id : String,
        @name : String,
        @organization_id : String? = nil,
        @description : String? = nil,
        @created_at : String? = nil,
        @updated_at : String? = nil,
      )
      end

      def self.from_any(payload : JSON::Any) : Project
        new(
          id: payload["id"].as_s,
          name: payload["name"].as_s,
          organization_id: payload["organization_id"]?.try(&.as_s?),
          description: payload["description"]?.try(&.as_s?),
          created_at: payload["created_at"]?.try(&.as_s?),
          updated_at: payload["updated_at"]?.try(&.as_s?),
        )
      end

      # Le projet `default` (créé automatiquement à l'inscription) a
      # son `id` égal à l'`organization_id`. Permet de l'identifier
      # sans se baser sur le nom (que l'utilisateur peut renommer).
      def default? : Bool
        @id == @organization_id
      end
    end
  end
end
