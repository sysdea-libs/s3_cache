# S3EtsCache

This implements a self-refreshing cache for S3 files, storing into ETS. This is designed for a limited number of small files which need to be readable quickly, but are fine to be stale for a short period. It's purpose of design was for distributing new CDN version ids to application servers, so that a new client deployment can be done purely by pushing new js/css to s3, and pierce any CDN caching.

```elixir
# Get file contents, will block for up to 5 seconds if a new request
S3EtsCache.get(%{bucket: "my-bucket", key: "path/to/my/file"})

# Touch file, setting up a cache process but not waiting for any data
# Useful during initialisation so first client request does not stall
S3EtsCache.touch(%{bucket: "my-bucket", key: "path/to/my/file"})

# Authorisation is provided on a file-by-file basis.
S3EtsCache.get(%{bucket: "my-private-bucket",
                 key: "my/secret/file",
                 region: "us-east-1",
                 auth: { "my_key", "my_secret" }})
```
