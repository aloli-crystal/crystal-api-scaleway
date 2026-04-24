require "./spec_helper"

describe ScalewayApi do
  it "expose une version" do
    ScalewayApi::VERSION.should eq("0.4.1")
  end

  it "liste les zones Scaleway les plus courantes" do
    ScalewayApi::ZONES.should contain("fr-par-2")
    ScalewayApi::ZONES.should contain("nl-ams-1")
    ScalewayApi::ZONES.should contain("pl-waw-2")
  end

  it "définit fr-par-2 comme zone par défaut" do
    ScalewayApi::DEFAULT_ZONE.should eq("fr-par-2")
  end
end
