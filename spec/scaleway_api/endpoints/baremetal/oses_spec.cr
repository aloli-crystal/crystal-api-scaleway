require "../../../spec_helper"

describe ScalewayApi::Endpoints::Baremetal::Oses do
  it "liste les OS disponibles d'une zone" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /zones\/fr-par-2\/os/,
      status: 200,
      body: %({
        "os": [
          {"id":"os-1","name":"debian-13","version":"13"},
          {"id":"os-2","name":"ubuntu-24.04","version":"24.04"},
          {"id":"os-3","name":"freebsd-14","version":"14.1"}
        ],
        "total_count": 3
      }),
    )

    oses = client.baremetal.oses.list
    oses.size.should eq(3)
    oses.map(&.name).should eq(["debian-13", "ubuntu-24.04", "freebsd-14"])
  end

  it "trouve un OS par préfixe de nom" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /zones\/fr-par-2\/os/,
      status: 200,
      body: %({
        "os": [
          {"id":"os-1","name":"debian-13"},
          {"id":"os-2","name":"ubuntu-24.04"}
        ]
      }),
    )

    match = client.baremetal.oses.find_by_name_prefix("debian")
    match.should_not be_nil
    match.not_nil!.id.should eq("os-1")
  end

  it "renvoie nil si aucun OS ne matche le préfixe" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /zones\/fr-par-2\/os/,
      status: 200,
      body: %({"os":[{"id":"os-1","name":"debian-13"}]}),
    )

    client.baremetal.oses.find_by_name_prefix("openbsd").should be_nil
  end

  it "récupère un OS par UUID" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /os\/os-1/,
      status: 200,
      body: %({"id":"os-1","name":"debian-13","version":"13"}),
    )

    os = client.baremetal.oses.get("os-1")
    os.id.should eq("os-1")
    os.name.should eq("debian-13")
    os.version.should eq("13")
  end
end
