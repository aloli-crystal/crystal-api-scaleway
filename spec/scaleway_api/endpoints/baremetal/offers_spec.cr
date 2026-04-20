require "../../../spec_helper"

describe ScalewayApi::Endpoints::Baremetal::Offers do
  it "liste les offres d'une zone" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /baremetal\/v1\/zones\/fr-par-2\/offers/,
      status: 200,
      body: %({
        "offers": [
          {
            "id":"offer-1",
            "name":"EM-A115X-SSD",
            "stock":"available",
            "bandwidth":1000000000,
            "commercial_range":"challenger"
          },
          {
            "id":"offer-2",
            "name":"EM-A210R-HDD",
            "stock":"empty"
          }
        ],
        "total_count": 2
      }),
    )

    offers = client.baremetal.offers.list
    offers.size.should eq(2)
    offers.first.id.should eq("offer-1")
    offers.first.name.should eq("EM-A115X-SSD")
    offers.first.stock.should eq("available")
    offers.first.bandwidth.should eq(1_000_000_000_i64)
    offers.last.stock.should eq("empty")
  end

  it "respecte la zone passée en argument" do
    transport = FakeTransport.new
    client = build_client(transport, zone: "fr-par-2")
    transport.stub(
      "GET",
      /zones\/nl-ams-1\/offers/,
      status: 200,
      body: %({"offers":[]}),
    )

    client.baremetal.offers.list(zone: "nl-ams-1")

    req = transport.requests.last
    req.url.should contain("/zones/nl-ams-1/offers")
  end

  it "récupère une offre par UUID" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /offers\/offer-1/,
      status: 200,
      body: %({"id":"offer-1","name":"EM-A115X-SSD"}),
    )

    offer = client.baremetal.offers.get("offer-1")
    offer.id.should eq("offer-1")
    offer.name.should eq("EM-A115X-SSD")
  end
end
