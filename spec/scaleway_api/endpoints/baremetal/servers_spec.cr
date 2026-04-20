require "../../../spec_helper"

describe ScalewayApi::Endpoints::Baremetal::Install do
  it "sérialise sans les champs nil" do
    install = ScalewayApi::Endpoints::Baremetal::Install.new(
      os_id: "os-1",
      hostname: "web01.aloli.fr",
      ssh_key_ids: ["key-1", "key-2"],
    )
    json = install.to_json_object
    json.should contain(%("os_id":"os-1"))
    json.should contain(%("hostname":"web01.aloli.fr"))
    json.should contain(%("ssh_key_ids":["key-1","key-2"]))
    json.should_not contain("user")
    json.should_not contain("password")
    json.should_not contain("service_user")
  end

  it "inclut user/password/service_user/service_password s'ils sont fournis" do
    install = ScalewayApi::Endpoints::Baremetal::Install.new(
      os_id: "os-1",
      hostname: "web01",
      ssh_key_ids: ["key-1"],
      user: "admin",
      password: "p@ss",
      service_user: "svc",
      service_password: "svcpass",
    )
    json = install.to_json_object
    json.should contain(%("user":"admin"))
    json.should contain(%("password":"p@ss"))
    json.should contain(%("service_user":"svc"))
    json.should contain(%("service_password":"svcpass"))
  end
end

describe ScalewayApi::Endpoints::Baremetal::Servers do
  it "liste les serveurs d'une zone" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /zones\/fr-par-2\/servers/,
      status: 200,
      body: %({
        "servers": [
          {"id":"srv-1","name":"web01","status":"ready","hostname":"web01.aloli.fr"},
          {"id":"srv-2","name":"web02","status":"installing","hostname":"web02.aloli.fr"}
        ],
        "total_count": 2
      }),
    )

    servers = client.baremetal.servers.list
    servers.size.should eq(2)
    servers.first.id.should eq("srv-1")
    servers.first.ready?.should be_true
    servers.last.installing?.should be_true
  end

  it "passe project_id en query si fourni" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("GET", /servers/, status: 200, body: %({"servers":[]}))

    client.baremetal.servers.list(project_id: "proj-xyz")

    req = transport.requests.last
    req.url.should contain("project_id=proj-xyz")
  end

  it "récupère un serveur par UUID et décode ses IPs" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /servers\/srv-1/,
      status: 200,
      body: %({
        "id":"srv-1",
        "name":"web01",
        "status":"ready",
        "hostname":"web01.aloli.fr",
        "ips":[
          {"id":"ip-1","address":"51.15.1.2","version":"IPv4","reverse":"web01.aloli.fr"},
          {"id":"ip-2","address":"2001:bc8::1","version":"IPv6","reverse":null}
        ],
        "tags":["prod","web"]
      }),
    )

    server = client.baremetal.servers.get("srv-1")
    server.ips.size.should eq(2)
    server.ips.first.address.should eq("51.15.1.2")
    server.ips.first.reverse.should eq("web01.aloli.fr")
    server.ips.last.version.should eq("IPv6")
    server.tags.should eq(["prod", "web"])
  end

  describe "#create" do
    it "POSTe offer_id + project_id + install en un seul appel" do
      transport = FakeTransport.new
      client = build_client(transport, project_id: "proj-abc")
      transport.stub(
        "POST",
        /zones\/fr-par-2\/servers$/,
        status: 200,
        body: %({"id":"srv-new","status":"delivering","hostname":"web01.aloli.fr"}),
      )

      install = ScalewayApi::Endpoints::Baremetal::Install.new(
        os_id: "os-1",
        hostname: "web01.aloli.fr",
        ssh_key_ids: ["key-1"],
      )

      server = client.baremetal.servers.create(
        offer_id: "offer-1",
        install: install,
        name: "web01",
        reverse: "web01.aloli.fr",
      )

      server.id.should eq("srv-new")
      server.status.should eq("delivering")

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.body.should contain(%("offer_id":"offer-1"))
      req.body.should contain(%("project_id":"proj-abc"))
      req.body.should contain(%("name":"web01"))
      req.body.should contain(%("reverse":"web01.aloli.fr"))
      req.body.should contain(%("install":{))
      req.body.should contain(%("os_id":"os-1"))
      req.body.should contain(%("ssh_key_ids":["key-1"]))
    end

    it "accepte des tags et une description" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /servers$/,
        status: 200,
        body: %({"id":"srv-new","status":"delivering"}),
      )

      install = ScalewayApi::Endpoints::Baremetal::Install.new(
        os_id: "os-1",
        hostname: "web",
        ssh_key_ids: ["k"],
      )

      client.baremetal.servers.create(
        offer_id: "o1",
        install: install,
        description: "serveur web prod",
        tags: ["prod", "web"],
      )

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.body.should contain(%("description":"serveur web prod"))
      req.body.should contain(%("tags":["prod","web"]))
    end
  end

  describe "#install" do
    it "POSTe /install avec l'objet install sérialisé" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /servers\/srv-1\/install/,
        status: 200,
        body: %({"id":"srv-1","status":"installing","hostname":"web01.aloli.fr"}),
      )

      install = ScalewayApi::Endpoints::Baremetal::Install.new(
        os_id: "os-1",
        hostname: "web01.aloli.fr",
        ssh_key_ids: ["key-1"],
      )

      server = client.baremetal.servers.install(server_id: "srv-1", install: install)
      server.installing?.should be_true

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.url.should contain("/servers/srv-1/install")
      req.body.should contain(%("os_id":"os-1"))
      req.body.should contain(%("hostname":"web01.aloli.fr"))
    end
  end

  describe "#reboot" do
    it "POSTe /reboot avec boot_type=normal par défaut" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /servers\/srv-1\/reboot/,
        status: 200,
        body: %({"id":"srv-1","status":"stopping","hostname":"web01.aloli.fr"}),
      )

      server = client.baremetal.servers.reboot(server_id: "srv-1")
      server.id.should eq("srv-1")
      server.status.should eq("stopping")

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.url.should contain("/baremetal/v1/zones/fr-par-2/servers/srv-1/reboot")
      req.body.should eq(%({"boot_type":"normal"}))
    end

    it "POSTe boot_type=rescue quand BootType::Rescue est passé" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /servers\/srv-1\/reboot/,
        status: 200,
        body: %({"id":"srv-1","status":"stopping"}),
      )

      client.baremetal.servers.reboot(
        server_id: "srv-1",
        boot_type: ScalewayApi::Endpoints::Baremetal::BootType::Rescue,
      )

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.body.should eq(%({"boot_type":"rescue"}))
    end

    it "accepte une zone explicite" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /zones\/nl-ams-1\/servers\/srv-9\/reboot/,
        status: 200,
        body: %({"id":"srv-9","status":"stopping"}),
      )

      client.baremetal.servers.reboot(
        server_id: "srv-9",
        boot_type: ScalewayApi::Endpoints::Baremetal::BootType::Rescue,
        zone: "nl-ams-1",
      )

      req = transport.requests.find { |r| r.method == "POST" }.not_nil!
      req.url.should contain("/baremetal/v1/zones/nl-ams-1/servers/srv-9/reboot")
    end

    it "décode le Server renvoyé (status, IPs)" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /servers\/srv-1\/reboot/,
        status: 200,
        body: %({
          "id":"srv-1",
          "status":"stopping",
          "hostname":"web01.aloli.fr",
          "ips":[{"id":"ip-1","address":"51.15.1.2","version":"IPv4"}]
        }),
      )

      server = client.baremetal.servers.reboot(
        server_id: "srv-1",
        boot_type: ScalewayApi::Endpoints::Baremetal::BootType::Rescue,
      )
      server.ips.size.should eq(1)
      server.ips.first.address.should eq("51.15.1.2")
      server.hostname.should eq("web01.aloli.fr")
    end

    it "remonte AuthenticationError sur 403 permissions_denied" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /servers\/srv-1\/reboot/,
        status: 403,
        body: %({"type":"permissions_denied","message":"insufficient permissions"}),
      )

      expect_raises(ScalewayApi::AuthenticationError, /403/) do
        client.baremetal.servers.reboot(server_id: "srv-1")
      end
    end

    it "remonte ApiError sur 409 (serveur en cours d'installation)" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "POST",
        /servers\/srv-1\/reboot/,
        status: 409,
        body: %({"type":"precondition_failed","message":"server is installing"}),
      )

      ex = expect_raises(ScalewayApi::ApiError, /409/) do
        client.baremetal.servers.reboot(
          server_id: "srv-1",
          boot_type: ScalewayApi::Endpoints::Baremetal::BootType::Rescue,
        )
      end
      ex.http_status.should eq(409)
      ex.error_code.should eq("precondition_failed")
    end
  end

  describe "BootType" do
    it "sérialise Normal et Rescue en minuscules" do
      ScalewayApi::Endpoints::Baremetal::BootType::Normal.to_api.should eq("normal")
      ScalewayApi::Endpoints::Baremetal::BootType::Rescue.to_api.should eq("rescue")
    end
  end

  describe "#update" do
    it "PATCHe le reverse" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "PATCH",
        /servers\/srv-1$/,
        status: 200,
        body: %({"id":"srv-1","status":"ready"}),
      )

      client.baremetal.servers.update(
        server_id: "srv-1",
        reverse: "web01.aloli.fr",
      )

      req = transport.requests.find { |r| r.method == "PATCH" }.not_nil!
      req.body.should eq(%({"reverse":"web01.aloli.fr"}))
    end
  end

  describe "#events" do
    it "liste les événements et décode leur statut" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /servers\/srv-1\/events/,
        status: 200,
        body: %({
          "events": [
            {"id":"ev-1","action":"install_server","status":"running","updated_at":"2026-04-18T10:00:00Z"},
            {"id":"ev-2","action":"install_server","status":"success","updated_at":"2026-04-18T10:45:00Z"}
          ]
        }),
      )

      events = client.baremetal.servers.events(server_id: "srv-1")
      events.size.should eq(2)
      events.first.action.should eq("install_server")
      events.first.success?.should be_false
      events.last.success?.should be_true
    end
  end

  describe "#delete" do
    it "DELETEe un serveur par UUID" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "DELETE",
        /servers\/srv-1$/,
        status: 200,
        body: %({"id":"srv-1","status":"deleting"}),
      )

      client.baremetal.servers.delete("srv-1")

      req = transport.requests.find { |r| r.method == "DELETE" }.not_nil!
      req.url.should contain("/servers/srv-1")
    end
  end

  describe "Server#ready? / installing? / failed?" do
    it "reconnaît les statuts terminaux et transitoires" do
      raw = JSON.parse(%({"id":"s","status":"ready"}))
      srv_ready = ScalewayApi::Endpoints::Baremetal::Server.from_any(raw)
      srv_ready.ready?.should be_true
      srv_ready.installing?.should be_false

      raw_installing = JSON.parse(%({"id":"s","status":"installing"}))
      ScalewayApi::Endpoints::Baremetal::Server.from_any(raw_installing).installing?.should be_true

      raw_error = JSON.parse(%({"id":"s","status":"error"}))
      ScalewayApi::Endpoints::Baremetal::Server.from_any(raw_error).failed?.should be_true
    end
  end
end
