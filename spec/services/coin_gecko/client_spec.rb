require "rails_helper"

RSpec.describe CoinGecko::Client do
  subject(:client) { described_class.new(api_key: "test-key", base_url: "https://api.coingecko.com/api/v3") }

  let(:endpoint) { "https://api.coingecko.com/api/v3/simple/price" }

  describe "#fetch_prices" do
    it "returns parsed prices for the given coin ids" do
      stub_request(:get, endpoint)
        .with(query: { ids: "bitcoin,ethereum", vs_currencies: "usd" })
        .to_return(
          status: 200,
          body: { bitcoin: { usd: 67000.12 }, ethereum: { usd: 3500.5 } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.fetch_prices(%w[bitcoin ethereum])

      expect(result).to eq(
        "bitcoin" => { "usd" => 67000.12 },
        "ethereum" => { "usd" => 3500.5 }
      )
    end

    it "sends the demo API key header" do
      stub = stub_request(:get, endpoint)
        .with(query: { ids: "bitcoin", vs_currencies: "usd" }, headers: { "x-cg-demo-api-key" => "test-key" })
        .to_return(status: 200, body: { bitcoin: { usd: 1 } }.to_json)

      client.fetch_prices(%w[bitcoin])

      expect(stub).to have_been_requested
    end

    it "raises CoinGecko::Client::Error on a non-2xx response" do
      stub_request(:get, endpoint)
        .with(query: { ids: "bitcoin", vs_currencies: "usd" })
        .to_return(status: 503, body: "Service Unavailable")

      expect { client.fetch_prices(%w[bitcoin]) }.to raise_error(CoinGecko::Client::Error)
    end

    it "raises CoinGecko::Client::Error when the request times out" do
      stub_request(:get, endpoint)
        .with(query: { ids: "bitcoin", vs_currencies: "usd" })
        .to_timeout

      expect { client.fetch_prices(%w[bitcoin]) }.to raise_error(CoinGecko::Client::Error)
    end

    it "raises CoinGecko::Client::Error on an unparsable response body" do
      stub_request(:get, endpoint)
        .with(query: { ids: "bitcoin", vs_currencies: "usd" })
        .to_return(status: 200, body: "not json")

      expect { client.fetch_prices(%w[bitcoin]) }.to raise_error(CoinGecko::Client::Error)
    end
  end
end
