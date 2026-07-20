# GET /prices/:symbol — serves the last cached price for a watchlisted coin.
#
# Deliberately never calls CoinGecko::Client itself: this controller only
# ever reads Rails.cache, so a request's latency and availability never
# depend on the external API. All fetching/writing happens in
# FetchCryptoPricesJob on its own schedule.
class PricesController < ApplicationController
  def show
    symbol = params[:symbol]

    unless CryptoPrice::WATCHLIST.include?(symbol)
      return render json: { error: "unknown symbol" }, status: :not_found
    end

    price = CryptoPrice.read(symbol)

    # Valid symbol, but the background job hasn't successfully fetched it
    # yet (e.g. right after first boot) — nothing to fall back to.
    if price.nil?
      return render json: { error: "price not available yet" }, status: :not_found
    end

    render json: {
      symbol: symbol,
      price: price[:price],
      currency: price[:currency],
      fetched_at: price[:fetched_at] # last successful fetch, not "now"
    }
  end
end
