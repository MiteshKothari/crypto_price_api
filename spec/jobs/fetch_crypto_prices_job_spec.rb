require "rails_helper"

RSpec.describe FetchCryptoPricesJob do
  after { Rails.cache.clear }

  let(:client) { instance_double(CoinGecko::Client) }

  describe "#perform" do
    context "when the CoinGecko fetch succeeds" do
      it "writes the latest price for every watchlisted symbol" do
        allow(client).to receive(:fetch_prices).with(CryptoPrice::WATCHLIST).and_return(
          "bitcoin" => { "usd" => 67000.12 },
          "ethereum" => { "usd" => 3500.5 },
          "dogecoin" => { "usd" => 0.15 },
          "solana" => { "usd" => 150.0 },
          "cardano" => { "usd" => 0.45 }
        )

        described_class.new.perform(client: client)

        expect(CryptoPrice.read("bitcoin")[:price]).to eq(67000.12)
        expect(CryptoPrice.read("bitcoin")[:currency]).to eq("usd")
        expect(CryptoPrice.read("ethereum")[:price]).to eq(3500.5)
      end

      it "records the fetch time on each written entry" do
        allow(client).to receive(:fetch_prices).and_return("bitcoin" => { "usd" => 67000.12 })

        freeze_time do
          described_class.new.perform(client: client)

          expect(CryptoPrice.read("bitcoin")[:fetched_at]).to eq(Time.current)
        end
      end
    end

    context "when the CoinGecko fetch fails" do
      it "leaves previously cached prices untouched (fallback behavior)" do
        CryptoPrice.write("bitcoin", price: 65000.0, currency: "usd", fetched_at: 1.minute.ago)
        allow(client).to receive(:fetch_prices).and_raise(CoinGecko::Client::Error, "service unavailable")

        described_class.new.perform(client: client)

        expect(CryptoPrice.read("bitcoin")[:price]).to eq(65000.0)
      end

      it "does not raise, so a single failed run does not error out the job" do
        allow(client).to receive(:fetch_prices).and_raise(CoinGecko::Client::Error, "service unavailable")

        expect { described_class.new.perform(client: client) }.not_to raise_error
      end
    end
  end
end
