require "rails_helper"

RSpec.describe "GET /prices/:symbol", type: :request do
  after { Rails.cache.clear }

  context "when the symbol is cached" do
    it "returns the cached price as JSON" do
      fetched_at = Time.zone.parse("2026-07-20T10:00:00Z")
      CryptoPrice.write("bitcoin", price: 67000.12, currency: "usd", fetched_at: fetched_at)

      get "/prices/bitcoin"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(
        "symbol" => "bitcoin",
        "price" => 67000.12,
        "currency" => "usd",
        "fetched_at" => fetched_at.as_json
      )
    end

    it "never calls out to CoinGecko itself" do
      CryptoPrice.write("bitcoin", price: 67000.12, currency: "usd", fetched_at: Time.current)

      expect { get "/prices/bitcoin" }.not_to raise_error
      expect(WebMock).not_to have_requested(:get, /coingecko/)
    end
  end

  context "when the symbol is not on the watchlist" do
    it "returns 404 with an error message" do
      get "/prices/not-a-real-coin"

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to eq("error" => "unknown symbol")
    end
  end

  context "when the symbol is valid but has never been fetched" do
    it "returns 404 with an error message" do
      get "/prices/bitcoin"

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to eq("error" => "price not available yet")
    end
  end
end
