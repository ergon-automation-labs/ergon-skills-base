ExUnit.start()

# Integration tests require DB + NATS
ExUnit.configure(exclude: [:integration, :nats_live])
