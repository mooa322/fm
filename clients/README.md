# Client licenses

Each client's encrypted bundle lives here as `<client-id>.enc`.
These files are produced by `tools/issue-client.sh` and are safe to be
public — they are AES-256 encrypted and useless without the client's key.

Delete a file (via `tools/revoke-client.sh`) to cut that client off.
