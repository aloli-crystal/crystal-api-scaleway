require "../spec_helper"

describe ScalewayApi::Client do
  describe "#initialize" do
    it "a une zone par défaut fr-par-2" do
      client = ScalewayApi::Client.new(secret_key: "s")
      client.default_zone.should eq("fr-par-2")
    end

    it "accepte une zone personnalisée" do
      client = ScalewayApi::Client.new(secret_key: "s", default_zone: "nl-ams-1")
      client.default_zone.should eq("nl-ams-1")
    end

    it "accepte une base_url personnalisée (proxy interne)" do
      client = ScalewayApi::Client.new(
        secret_key: "s",
        base_url: "https://api-proxy.aloli.fr",
      )
      client.base_url.should eq("https://api-proxy.aloli.fr")
    end
  end

  describe "#resolve_zone" do
    it "priorise l'argument explicite" do
      client = ScalewayApi::Client.new(secret_key: "s", default_zone: "fr-par-2")
      client.resolve_zone("pl-waw-2").should eq("pl-waw-2")
    end

    it "retombe sur default_zone si nil" do
      client = ScalewayApi::Client.new(secret_key: "s", default_zone: "nl-ams-1")
      client.resolve_zone(nil).should eq("nl-ams-1")
    end
  end

  describe "#resolve_project_id" do
    it "priorise l'argument explicite" do
      client = ScalewayApi::Client.new(secret_key: "s", default_project_id: "proj-A")
      client.resolve_project_id("proj-B").should eq("proj-B")
    end

    it "retombe sur default_project_id si nil" do
      client = ScalewayApi::Client.new(secret_key: "s", default_project_id: "proj-A")
      client.resolve_project_id(nil).should eq("proj-A")
    end

    it "lève si aucun project_id n'est configuré" do
      client = ScalewayApi::Client.new(secret_key: "s")
      expect_raises(ArgumentError, /project_id/) { client.resolve_project_id(nil) }
    end
  end

  describe "#call (auth + en-têtes)" do
    it "pose X-Auth-Token sur chaque requête" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /ssh-keys/, status: 200, body: %({"ssh_keys":[]}))

      client.call("GET", "/iam/v1alpha1/ssh-keys")

      req = transport.requests.last
      req.headers["X-Auth-Token"].should eq("test-secret")
      req.headers["Content-Type"].should eq("application/json")
      req.headers["Accept"].should eq("application/json")
    end

    it "construit l'URL sur base_url + path" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /iam\/v1alpha1\/ssh-keys/, status: 200, body: %({"ssh_keys":[]}))

      client.call("GET", "/iam/v1alpha1/ssh-keys")

      req = transport.requests.last
      req.url.should eq("https://api.scaleway.com/iam/v1alpha1/ssh-keys")
    end

    it "encode la query string" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /ssh-keys\?/, status: 200, body: %({"ssh_keys":[]}))

      client.call(
        "GET",
        "/iam/v1alpha1/ssh-keys",
        query: {"project_id" => "proj-1", "page_size" => "50"},
      )

      req = transport.requests.last
      req.url.should contain("project_id=proj-1")
      req.url.should contain("page_size=50")
    end

    it "sérialise le corps en JSON compact" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("POST", /ssh-keys/, status: 200, body: %({"id":"k1","name":"x","public_key":"ssh"}))

      client.call(
        "POST",
        "/iam/v1alpha1/ssh-keys",
        body: {"name" => "x", "public_key" => "ssh"},
      )

      req = transport.requests.last
      req.body.should eq(%({"name":"x","public_key":"ssh"}))
    end
  end

  describe "#call (gestion d'erreurs)" do
    it "lève NotFound sur 404" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /servers\/missing/,
        status: 404,
        body: %({"type":"resource_not_found","message":"Not found"}),
      )

      expect_raises(ScalewayApi::NotFound, /404/) do
        client.call("GET", "/baremetal/v1/zones/fr-par-2/servers/missing")
      end
    end

    it "lève AuthenticationError sur 401" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /ssh-keys/, status: 401, body: %({"type":"permissions_denied"}))

      expect_raises(ScalewayApi::AuthenticationError, /401/) do
        client.call("GET", "/iam/v1alpha1/ssh-keys")
      end
    end

    it "lève AuthenticationError sur 403" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /ssh-keys/, status: 403, body: %({"type":"permissions_denied"}))

      expect_raises(ScalewayApi::AuthenticationError, /403/) do
        client.call("GET", "/iam/v1alpha1/ssh-keys")
      end
    end

    it "lève RateLimited sur 429 et tente d'extraire retry_after" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /throttle/,
        status: 429,
        body: %({"type":"quotas_exceeded","message":"slow down","retry_after":15}),
      )

      exc = expect_raises(ScalewayApi::RateLimited) do
        client.call("GET", "/throttle")
      end
      exc.retry_after.should eq(15)
    end

    it "lève ApiError sur 500 et capture le champ type comme error_code" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /boom/,
        status: 500,
        body: %({"type":"internal_server_error","message":"boom"}),
      )

      exc = expect_raises(ScalewayApi::ApiError, /500/) do
        client.call("GET", "/boom")
      end
      exc.http_status.should eq(500)
      exc.error_code.should eq("internal_server_error")
    end

    it "renvoie nil sur 204 / corps vide" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("DELETE", /ssh-keys\/k1/, status: 204, body: "")

      result = client.call("DELETE", "/iam/v1alpha1/ssh-keys/k1")
      result.should be_nil
    end
  end
end
