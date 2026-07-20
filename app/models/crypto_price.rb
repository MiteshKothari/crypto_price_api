# Read/write access to the cached crypto prices. Not an ActiveRecord model —
# prices live in Rails.cache (Solid Cache); this class centralizes the cache
# key format and stored shape so the job (writer) and controller (reader)
# stay in sync without duplicating either detail.
class CryptoPrice
  # The only symbols FetchCryptoPricesJob polls and PricesController serves.
  # CoinGecko coin ids, not ticker symbols (e.g. "bitcoin", not "BTC").
  WATCHLIST = %w[bitcoin ethereum dogecoin solana cardano].freeze

  # Cache key a given symbol is stored/looked up under.
  def self.cache_key(symbol)
    "crypto_price:#{symbol}"
  end

  # Returns the cached { price:, currency:, fetched_at: } Hash for a symbol,
  # or nil if nothing has been successfully fetched for it yet.
  def self.read(symbol)
    Rails.cache.read(cache_key(symbol))
  end

  # Overwrites the cached price for a symbol. Called only from
  # FetchCryptoPricesJob — see that class for why a failed fetch simply
  # skips this call instead of writing an error state.
  def self.write(symbol, price:, currency:, fetched_at:)
    Rails.cache.write(cache_key(symbol), { price: price, currency: currency, fetched_at: fetched_at })
  end
end
