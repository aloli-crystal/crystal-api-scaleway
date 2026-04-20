require "spec"
require "../src/scaleway_api"

# Transport HTTP factice : stocke les requêtes reçues et renvoie des
# réponses pré-programmées. Purement stdlib, aucune dépendance externe.
#
# Usage dans les specs :
#
# ```
# transport = FakeTransport.new
# transport.stub("GET", /ssh-keys/, status: 200, body: %({"ssh_keys":[]}))
#
# client = ScalewayApi::Client.new(
#   secret_key: "secret",
#   default_project_id: "proj-uuid",
#   transport: transport,
# )
# client.ssh_keys.list.should be_empty
#
# # Inspection des requêtes émises :
# transport.requests.last.headers["X-Auth-Token"].should eq("secret")
# ```
class FakeTransport < ScalewayApi::HttpTransport
  record Request,
    method : String,
    url : String,
    headers : HTTP::Headers,
    body : String

  record Stub,
    method : String,
    url_pattern : Regex,
    status : Int32,
    body : String

  getter requests = [] of Request
  getter stubs = [] of Stub

  def stub(method : String, url_pattern : Regex, status : Int32, body : String) : Nil
    @stubs << Stub.new(method: method, url_pattern: url_pattern, status: status, body: body)
  end

  def request(method, url, headers, body) : {Int32, String}
    @requests << Request.new(method: method, url: url, headers: headers, body: body)

    match = @stubs.reverse.find { |s| s.method == method && s.url_pattern.matches?(url) }
    unless match
      raise "Aucun stub ne correspond à #{method} #{url} (stubs déclarés : " \
            "#{@stubs.map { |s| "#{s.method} #{s.url_pattern.source}" }.join(", ")})"
    end
    {match.status, match.body}
  end
end

# Fabrique un client Scaleway lié à un FakeTransport, avec un
# `default_project_id` déjà fixé pour simplifier les specs.
def build_client(
  transport : FakeTransport,
  project_id : String = "proj-11111111-2222-3333-4444-555555555555",
  zone : String = "fr-par-2",
) : ScalewayApi::Client
  ScalewayApi::Client.new(
    secret_key: "test-secret",
    default_project_id: project_id,
    default_zone: zone,
    transport: transport,
  )
end
