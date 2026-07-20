# crypto_price_api
This application provides a REST API to retrieve cryptocurrency prices. Prices are not fetched from CoinGecko on every request. Instead, a background job updates the latest prices every minute and stores them locally. The API serves these stored values, ensuring fast responses and continued availability even if CoinGecko is temporarily unavailable.
