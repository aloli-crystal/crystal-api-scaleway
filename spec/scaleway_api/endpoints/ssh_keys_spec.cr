require "../../spec_helper"

describe ScalewayApi::Endpoints::SshKeys do
  it "liste les clés du projet (décapsule ssh_keys)" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /iam\/v1alpha1\/ssh-keys\?/,
      status: 200,
      body: %({
        "ssh_keys": [
          {"id":"key-1","name":"laptop","public_key":"ssh-ed25519 AAAA"},
          {"id":"key-2","name":"desktop","public_key":"ssh-ed25519 BBBB"}
        ],
        "total_count": 2
      }),
    )

    keys = client.ssh_keys.list
    keys.size.should eq(2)
    keys.first.id.should eq("key-1")
    keys.first.name.should eq("laptop")
    keys.last.name.should eq("desktop")
  end

  it "passe le project_id par défaut dans la query" do
    transport = FakeTransport.new
    client = build_client(transport, project_id: "proj-abc")
    transport.stub("GET", /ssh-keys/, status: 200, body: %({"ssh_keys":[]}))

    client.ssh_keys.list

    req = transport.requests.last
    req.url.should contain("project_id=proj-abc")
  end

  it "accepte un project_id explicite qui prime sur le défaut" do
    transport = FakeTransport.new
    client = build_client(transport, project_id: "proj-default")
    transport.stub("GET", /ssh-keys/, status: 200, body: %({"ssh_keys":[]}))

    client.ssh_keys.list(project_id: "proj-override")

    req = transport.requests.last
    req.url.should contain("project_id=proj-override")
  end

  it "renvoie un tableau vide quand ssh_keys est absent" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("GET", /ssh-keys/, status: 200, body: %({"total_count":0}))

    client.ssh_keys.list.should be_empty
  end

  it "récupère une clé par UUID" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub(
      "GET",
      /ssh-keys\/key-1/,
      status: 200,
      body: %({
        "id":"key-1",
        "name":"laptop",
        "public_key":"ssh-ed25519 AAAA me@host",
        "fingerprint":"SHA256:abc",
        "project_id":"proj-1",
        "created_at":"2026-04-18T10:00:00Z"
      }),
    )

    key = client.ssh_keys.get("key-1")
    key.id.should eq("key-1")
    key.name.should eq("laptop")
    key.fingerprint.should eq("SHA256:abc")
  end

  it "POSTe name/public_key/project_id à la création" do
    transport = FakeTransport.new
    client = build_client(transport, project_id: "proj-abc")
    transport.stub(
      "POST",
      /ssh-keys/,
      status: 200,
      body: %({"id":"key-new","name":"laptop","public_key":"ssh-ed25519 AAAA"}),
    )

    key = client.ssh_keys.create(name: "laptop", public_key: "ssh-ed25519 AAAA")
    key.id.should eq("key-new")

    req = transport.requests.find { |r| r.method == "POST" }.not_nil!
    req.body.should contain(%("name":"laptop"))
    req.body.should contain(%("public_key":"ssh-ed25519 AAAA"))
    req.body.should contain(%("project_id":"proj-abc"))
  end

  it "DELETEe une clé par UUID" do
    transport = FakeTransport.new
    client = build_client(transport)
    transport.stub("DELETE", /ssh-keys\/key-1/, status: 204, body: "")

    client.ssh_keys.delete("key-1")

    req = transport.requests.find { |r| r.method == "DELETE" }.not_nil!
    req.url.should contain("/iam/v1alpha1/ssh-keys/key-1")
  end
end
