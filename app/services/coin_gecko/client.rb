require "net/http"
require "json"

module CoinGecko
  # Thin HTTP wrapper around the CoinGecko "simple price" endpoint.
  # Raises CoinGecko::Client::Error for any failure (network, timeout, non-2xx,
  # unparsable body) so callers only need to rescue one error class.
  #
  # Usage:
  #   client = CoinGecko::Client.new(api_key: ENV["CG_API_KEY"])
  #   client.fetch_prices(%w[bitcoin ethereum]) # => {"bitcoin"=>{"usd"=>67000.12}, ...}
  class Client
    # Raised for every failure mode (HTTP error, timeout, network error,
    # unparsable body) so callers only ever need to rescue one class.
    class Error < StandardError; end

    # CoinGecko's free/demo-tier auth header (paid "Pro" plans use a
    # different header and host — see README for details).
    API_KEY_HEADER = "x-cg-demo-api-key"

    # Kept short since this client is called once a minute by a background
    # job — a hung request shouldn't be allowed to block the next run.
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5

    def initialize(api_key:, base_url: "https://api.coingecko.com/api/v3")
      @api_key = api_key
      @base_url = base_url
    end

    # Fetches current prices for the given CoinGecko coin ids.
    #
    # ids         - Array of CoinGecko coin ids, e.g. %w[bitcoin ethereum]
    # vs_currency - currency to price against (default "usd")
    #
    # Returns a Hash like {"bitcoin" => {"usd" => 67000.12}, ...}.
    # Raises CoinGecko::Client::Error on any failure.
    def fetch_prices(ids, vs_currency: "usd")
      uri = URI.join("#{@base_url}/", "simple/price")
      uri.query = URI.encode_www_form(ids: ids.join(","), vs_currencies: vs_currency)

      response = get(uri)
      raise Error, "CoinGecko responded with #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      # CoinGecko returned 2xx but a body we can't parse — treat it the same
      # as any other failure so callers have one error class to rescue.
      raise Error, "CoinGecko returned an unparsable response: #{e.message}"
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "CoinGecko request failed: #{e.message}"
    end

    private

    # Issues the actual GET request with the demo API key header attached.
    def get(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri)
        request[API_KEY_HEADER] = @api_key
        http.request(request)
      end
    end
  end
end
