require "http/client"
require "json"

1000.times do
  spawn do
    response = HTTP::Client.post("http://localhost:9999/collections", body: { name1: "My Collection" }.to_json)
    puts response.body
  end
end

sleep 1
