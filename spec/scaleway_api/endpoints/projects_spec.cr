require "../../spec_helper"

describe ScalewayApi::Endpoints::Projects do
  describe "#list" do
    it "GET /account/v3/projects?organization_id=... et décode les projets" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /account\/v3\/projects/,
        status: 200,
        body: %({
          "total_count": 2,
          "projects": [
            {
              "id": "b7014896-1c2d-43b0-8def-05c4090c74b2",
              "name": "default",
              "organization_id": "b7014896-1c2d-43b0-8def-05c4090c74b2",
              "description": "",
              "created_at": "2025-11-17T13:40:15.525803Z"
            },
            {
              "id": "a1b2c3d4-1234-5678-9abc-def012345678",
              "name": "production",
              "organization_id": "b7014896-1c2d-43b0-8def-05c4090c74b2"
            }
          ]
        }),
      )

      projects = client.projects.list(organization_id: "b7014896-1c2d-43b0-8def-05c4090c74b2")
      projects.size.should eq(2)
      projects.first.id.should eq("b7014896-1c2d-43b0-8def-05c4090c74b2")
      projects.first.name.should eq("default")
      projects.first.default?.should be_true
      projects.last.name.should eq("production")
      projects.last.default?.should be_false
    end

    it "passe organization_id en query string (filtre obligatoire côté API)" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /projects/, status: 200, body: %({"projects":[]}))

      client.projects.list(organization_id: "org-uuid")

      req = transport.requests.last
      req.url.should contain("organization_id=org-uuid")
    end

    it "retourne un tableau vide si l'API renvoie projects: []" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub("GET", /projects/, status: 200, body: %({"projects":[]}))

      client.projects.list(organization_id: "org-uuid").should be_empty
    end
  end

  describe "#get" do
    it "GET /account/v3/projects/<id>" do
      transport = FakeTransport.new
      client = build_client(transport)
      transport.stub(
        "GET",
        /projects\/proj-1/,
        status: 200,
        body: %({"id":"proj-1","name":"production","organization_id":"org-1"}),
      )

      project = client.projects.get("proj-1")
      project.id.should eq("proj-1")
      project.name.should eq("production")
      project.organization_id.should eq("org-1")
    end
  end

  describe "Project#default?" do
    it "vrai quand id == organization_id (projet `default` créé à l'inscription)" do
      project = ScalewayApi::Endpoints::Project.new(
        id: "same-uuid",
        name: "default",
        organization_id: "same-uuid",
      )
      project.default?.should be_true
    end

    it "faux quand id != organization_id (projet créé après coup)" do
      project = ScalewayApi::Endpoints::Project.new(
        id: "proj-uuid",
        name: "production",
        organization_id: "org-uuid",
      )
      project.default?.should be_false
    end

    it "faux quand organization_id est nil" do
      project = ScalewayApi::Endpoints::Project.new(
        id: "proj-uuid",
        name: "test",
      )
      project.default?.should be_false
    end
  end
end
