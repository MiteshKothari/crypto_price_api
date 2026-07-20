require "rails_helper"

RSpec.describe CryptoPrice do
  after { Rails.cache.clear }

  describe ".read" do
    it "returns nil when nothing has been cached for the symbol" do
      expect(described_class.read("bitcoin")).to be_nil
    end

    it "returns the previously written value" do
      fetched_at = Time.zone.parse("2026-07-20T10:00:00Z")

      described_class.write("bitcoin", price: 67000.12, currency: "usd", fetched_at: fetched_at)

      expect(described_class.read("bitcoin")).to eq(
        price: 67000.12, currency: "usd", fetched_at: fetched_at
      )
    end
  end

  describe ".write" do
    it "stores values independently per symbol" do
      described_class.write("bitcoin", price: 67000.12, currency: "usd", fetched_at: Time.current)
      described_class.write("ethereum", price: 3500.5, currency: "usd", fetched_at: Time.current)

      expect(described_class.read("bitcoin")[:price]).to eq(67000.12)
      expect(described_class.read("ethereum")[:price]).to eq(3500.5)
    end

    it "overwrites the previous value for the same symbol" do
      described_class.write("bitcoin", price: 67000.12, currency: "usd", fetched_at: Time.current)
      described_class.write("bitcoin", price: 68000.0, currency: "usd", fetched_at: Time.current)

      expect(described_class.read("bitcoin")[:price]).to eq(68000.0)
    end
  end

  describe ".cache_key" do
    it "namespaces the key by symbol" do
      expect(described_class.cache_key("bitcoin")).to eq("crypto_price:bitcoin")
    end
  end

  describe "::WATCHLIST" do
    it "is a non-empty list of CoinGecko coin ids" do
      expect(described_class::WATCHLIST).to be_an(Array)
      expect(described_class::WATCHLIST).not_to be_empty
      expect(described_class::WATCHLIST).to include("bitcoin", "ethereum")
    end
  end
end
