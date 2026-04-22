require "../../../spec_helper"

describe ScalewayApi::Endpoints::Domain::Records do
  describe "#list" do
    it "liste les records d'une zone et décapsule `records`" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /domain\/v2beta1\/dns-zones\/aloli\.net\/records/,
        status: 200,
        body: %({
          "records": [
            {"id":"r-1","name":"loulou","type":"CNAME","data":"ns.example.eu.","ttl":3600,"priority":0},
            {"id":"r-2","name":"backup","type":"CNAME","data":"ns2.example.eu.","ttl":3600,"priority":0}
          ],
          "total_count": 2
        }),
      )

      recs = client.domain.records.list("aloli.net")
      recs.size.should eq(2)
      recs.first.name.should eq("loulou")
      recs.first.data.should eq("ns.example.eu.")
    end

    it "filtre par type et name via query" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /dns-zones\/aloli\.net\/records.*type=CNAME.*name=loulou/,
        status: 200,
        body: %({"records":[{"id":"r-1","name":"loulou","type":"CNAME","data":"ns.example.","ttl":3600}]}),
      )

      recs = client.domain.records.list("aloli.net", type: "CNAME", name: "loulou")
      recs.size.should eq(1)
    end
  end

  describe "#set" do
    it "PATCH un changeset `set` avec id_fields + records" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "PATCH",
        /dns-zones\/aloli\.net\/records/,
        status: 200,
        body: "{}",
      )

      client.domain.records.set(
        zone: "aloli.net",
        type: "CNAME",
        name: "loulou",
        values: ["ns3156789.ip-51-83-6.eu."],
        ttl: 3600,
      )

      req = transport.requests.find! { |r| r.method == "PATCH" }
      req.body.should contain(%("set"))
      req.body.should contain(%("id_fields"))
      req.body.should contain(%("name":"loulou"))
      req.body.should contain(%("type":"CNAME"))
      req.body.should contain(%("data":"ns3156789.ip-51-83-6.eu."))
    end
  end

  describe "#delete" do
    it "PATCH un changeset `delete` avec id_fields" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("PATCH", /dns-zones\/aloli\.net\/records/, status: 200, body: "{}")

      client.domain.records.delete("aloli.net", type: "CNAME", name: "loulou")

      req = transport.requests.find! { |r| r.method == "PATCH" }
      req.body.should contain(%("delete"))
      req.body.should contain(%("name":"loulou"))
    end
  end

  describe "#ensure" do
    it "ne fait rien si le record existe déjà avec la bonne valeur" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /dns-zones\/aloli\.net\/records/,
        status: 200,
        body: %({"records":[{"id":"r-1","name":"loulou","type":"CNAME","data":"ns.example.","ttl":3600}]}),
      )

      client.domain.records.ensure("aloli.net", "CNAME", "loulou", "ns.example.")

      transport.requests.any? { |r| r.method == "PATCH" }.should be_false
    end

    it "appelle PATCH set si la valeur diffère" do
      transport = FakeTransport.new
      client = build_client(transport)
      # Premier GET : ancien record. Deuxième GET (après set) : nouveau.
      transport.stub(
        "GET",
        /records/,
        status: 200,
        body: %({"records":[{"id":"r-1","name":"loulou","type":"CNAME","data":"ancien.","ttl":3600}]}),
      )
      transport.stub("PATCH", /records/, status: 200, body: "{}")

      client.domain.records.ensure("aloli.net", "CNAME", "loulou", "nouveau.")

      patch = transport.requests.find! { |r| r.method == "PATCH" }
      patch.body.should contain(%("data":"nouveau."))
    end

    it "crée le record (PATCH set) s'il n'existe pas" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /records/,
        status: 200,
        body: %({"records":[]}),
      )
      transport.stub("PATCH", /records/, status: 200, body: "{}")

      client.domain.records.ensure("aloli.net", "CNAME", "loulou", "ns.example.")

      transport.requests.any? { |r| r.method == "PATCH" }.should be_true
    end
  end
end
