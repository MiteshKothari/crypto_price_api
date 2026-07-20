# Runs every minute (see config/recurring.yml) to refresh cached crypto prices.
# On a successful CoinGecko fetch, overwrites the cache for every watchlisted
# symbol. On failure, logs and leaves the cache untouched — the previously
# cached price keeps being served, which is the "fallback to last known
# price" behavior described in the requirements.
class FetchCryptoPricesJob < ApplicationJob
  queue_as :default

  # client kwarg defaults to a real CoinGecko::Client but can be swapped for
  # a test double in specs — that's what lets the job spec assert on
  # orchestration (which symbols get written, fallback on error) without
  # ever touching HTTP.
  def perform(client: CoinGecko::Client.new(api_key: ENV["CG_API_KEY"]))
    prices = client.fetch_prices(CryptoPrice::WATCHLIST)

    # One API call returns every watchlisted symbol at once (CoinGecko
    # supports batching ids), each keyed by currency, e.g.
    # {"bitcoin" => {"usd" => 67000.12}}. Write each price individually so a
    # partial/odd response still updates whatever symbols it did include.
    prices.each do |symbol, currency_prices|
      currency_prices.each do |currency, price|
        CryptoPrice.write(symbol, price: price, currency: currency, fetched_at: Time.current)
      end
    end
  rescue CoinGecko::Client::Error => e
    # Deliberately swallow the error instead of re-raising: the cache is
    # simply left as-is, so PricesController keeps serving the last known
    # price. This *is* the fallback behavior — there's no separate code path
    # for it. Logging still surfaces the outage for observability.
    Rails.logger.warn("FetchCryptoPricesJob: CoinGecko fetch failed, serving last known prices (#{e.message})")
  end
end
