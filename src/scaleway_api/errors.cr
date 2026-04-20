module ScalewayApi
  # Base de la hiérarchie d'exceptions ScalewayApi.
  #
  # Toutes les erreurs remontées par ce shard descendent de
  # `ScalewayApi::Error`, ce qui permet à l'appelant de rattraper
  # l'ensemble avec un seul `rescue`.
  class Error < Exception
  end

  # Erreur d'authentification : `secret_key` invalide ou expirée,
  # permissions IAM insuffisantes. Correspond à HTTP 401/403 côté Scaleway.
  class AuthenticationError < Error
  end

  # Ressource inexistante. Correspond à HTTP 404.
  class NotFound < Error
  end

  # Dépassement de quota. Correspond à HTTP 429. Scaleway renvoie parfois
  # un en-tête `Retry-After`; l'appelant peut aussi l'extraire du corps.
  class RateLimited < Error
    getter retry_after : Int32?

    def initialize(message : String, @retry_after : Int32? = nil)
      super(message)
    end
  end

  # Erreur générique remontée par l'API Scaleway : message, code HTTP et
  # `error_code` (champ `type` du corps JSON, ex. `"invalid_argument"`,
  # `"quotas_exceeded"`, `"resource_not_found"`).
  #
  # Scaleway suit le format `{"type": "...", "message": "...", "details": [...]}`.
  class ApiError < Error
    getter http_status : Int32
    getter error_code : String?

    def initialize(message : String, @http_status : Int32, @error_code : String? = nil)
      super(message)
    end
  end
end
