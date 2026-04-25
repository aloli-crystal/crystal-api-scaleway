require "http/client"
require "json"
require "uri"

require "./errors"

module ScalewayApi
  # URL de base de l'API Scaleway (unique, contrairement à OVH qui
  # distingue eu/ca/us). La zone fait partie du chemin (`/zones/{zone}/...`),
  # pas du hostname.
  BASE_URL = "https://api.scaleway.com"

  # Zones supportées au moment de l'écriture. Cette liste est purement
  # indicative : le client accepte n'importe quelle chaîne pour `zone`,
  # ce qui évite à ce shard de devoir être maintenu au rythme des
  # ouvertures de nouveaux datacenters Scaleway.
  ZONES = %w[
    fr-par-1
    fr-par-2
    fr-par-3
    nl-ams-1
    nl-ams-2
    nl-ams-3
    pl-waw-1
    pl-waw-2
    pl-waw-3
  ]

  # Zone par défaut si ni le client ni l'appel ne la précisent.
  DEFAULT_ZONE = "fr-par-2"

  # Transport HTTP abstrait. Permet d'injecter un double en test.
  #
  # Une implémentation doit retourner un tuple `{status, body}`. Le
  # `Client` se charge de décoder le JSON et de lever les exceptions.
  abstract class HttpTransport
    abstract def request(
      method : String,
      url : String,
      headers : HTTP::Headers,
      body : String,
    ) : {Int32, String}
  end

  # Transport par défaut, basé sur `HTTP::Client` de la stdlib.
  class DefaultHttpTransport < HttpTransport
    def request(method, url, headers, body) : {Int32, String}
      response = HTTP::Client.exec(
        method: method,
        url: url,
        headers: headers,
        body: body.empty? ? nil : body,
      )
      {response.status_code, response.body}
    end
  end

  # Client Scaleway REST API v1.
  #
  # Authentification beaucoup plus simple que l'API OVH : un seul en-tête
  # `X-Auth-Token` porté par chaque requête. Pas de signature, pas de
  # synchronisation d'horloge, pas de consumer key.
  #
  # La `secret_key` est celle d'une clé API IAM Scaleway (générée sur
  # https://console.scaleway.com/iam/api-keys). `default_project_id` est
  # nécessaire pour créer des ressources (clés SSH, serveurs) : Scaleway
  # exige la présence du projet dans le corps de la requête.
  #
  # ```
  # client = ScalewayApi::Client.new(
  #   secret_key: ENV["SCW_SECRET_KEY"],
  #   default_project_id: ENV["SCW_DEFAULT_PROJECT_ID"],
  #   default_zone: "fr-par-2",
  # )
  # ```
  class Client
    getter secret_key : String
    getter default_project_id : String?
    getter default_zone : String
    getter base_url : String

    # Injection du transport HTTP (par défaut `DefaultHttpTransport`).
    # En test, passer un double qui renvoie `{status, body}` prédéfini.
    property transport : HttpTransport

    def initialize(
      @secret_key : String,
      @default_project_id : String? = nil,
      @default_zone : String = DEFAULT_ZONE,
      @base_url : String = BASE_URL,
      @transport : HttpTransport = DefaultHttpTransport.new,
    )
    end

    # Résout la zone à utiliser : argument explicite en priorité, sinon
    # `default_zone` du client.
    def resolve_zone(zone : String?) : String
      zone || @default_zone
    end

    # Résout le project_id à utiliser : argument explicite en priorité,
    # sinon `default_project_id` du client. Lève si aucun n'est défini
    # *et* que l'endpoint en exige un.
    def resolve_project_id(project_id : String?) : String
      project_id || @default_project_id || raise ArgumentError.new(
        "project_id manquant : précisez-le en argument ou via " \
        "`default_project_id:` à la construction du client.",
      )
    end

    # Effectue un appel API.
    #
    # * `method`      : `"GET"`, `"POST"`, `"PUT"`, `"PATCH"`, `"DELETE"`.
    # * `path`        : chemin relatif à `base_url`
    #                   (ex. `"/iam/v1alpha1/ssh-keys"` ou
    #                   `"/baremetal/v1/zones/fr-par-2/servers"`).
    # * `query`       : table de paramètres encodée dans l'URL.
    # * `body`        : objet JSON-sérialisable (ou `nil`).
    #
    # Retourne le corps parsé en `JSON::Any` (ou `nil` si corps vide).
    def call(
      method : String,
      path : String,
      query : Hash(String, String)? = nil,
      body = nil,
    ) : JSON::Any?
      url = build_url(path, query)
      body_str = serialize_body(body)
      headers = HTTP::Headers{
        "Accept"       => "application/json",
        "Content-Type" => "application/json",
        "X-Auth-Token" => @secret_key,
      }

      status, response_body = @transport.request(method, url, headers, body_str)
      handle_response(status, response_body, method, path)
    end

    private def build_url(path : String, query : Hash(String, String)?) : String
      full = @base_url + (path.starts_with?("/") ? path : "/#{path}")
      if query && !query.empty?
        pairs = query.map { |k, v| "#{URI.encode_path_segment(k)}=#{URI.encode_path_segment(v)}" }
        full + "?" + pairs.join("&")
      else
        full
      end
    end

    private def serialize_body(body) : String
      case body
      when Nil
        ""
      when String
        body
      else
        body.to_json
      end
    end

    private def handle_response(status : Int32, body : String, method : String, path : String) : JSON::Any?
      case status
      when 200..299
        return nil if body.empty?
        JSON.parse(body)
      when 401, 403
        raise AuthenticationError.new(format_error(status, body, method, path))
      when 404
        raise NotFound.new(format_error(status, body, method, path))
      when 429
        retry_after = extract_retry_after(body)
        raise RateLimited.new(format_error(status, body, method, path), retry_after)
      else
        error_code = extract_error_code(body)
        raise ApiError.new(format_error(status, body, method, path), status, error_code)
      end
    end

    private def format_error(status : Int32, body : String, method : String, path : String) : String
      "Scaleway API #{method} #{path} → HTTP #{status} : #{body.empty? ? "(corps vide)" : body}"
    end

    # Scaleway pose le `type` (ex. `"invalid_argument"`, `"quotas_exceeded"`,
    # `"resource_not_found"`, `"permissions_denied"`) dans le corps. On
    # l'expose tel quel dans `ApiError#error_code`.
    private def extract_error_code(body : String) : String?
      parsed = JSON.parse(body)
      parsed["type"]?.try(&.as_s?)
    rescue
      nil
    end

    private def extract_retry_after(body : String) : Int32?
      parsed = JSON.parse(body)
      parsed["retry_after"]?.try(&.as_i?) || parsed["details"]?.try do |d|
        d.as_a?.try(&.first?).try(&.["retry_after"]?).try(&.as_i?)
      end
    rescue
      nil
    end

    # Accès paresseux aux endpoints. Chaque sous-client réutilise le même
    # `self`, donc la même config et le même transport.

    def ssh_keys : Endpoints::SshKeys
      @ssh_keys ||= Endpoints::SshKeys.new(self)
    end

    def baremetal : Endpoints::Baremetal::Namespace
      @baremetal ||= Endpoints::Baremetal::Namespace.new(self)
    end

    def domain : Endpoints::Domain::Namespace
      @domain ||= Endpoints::Domain::Namespace.new(self)
    end

    def projects : Endpoints::Projects
      @projects ||= Endpoints::Projects.new(self)
    end

    @ssh_keys : Endpoints::SshKeys?
    @baremetal : Endpoints::Baremetal::Namespace?
    @domain : Endpoints::Domain::Namespace?
    @projects : Endpoints::Projects?
  end
end
