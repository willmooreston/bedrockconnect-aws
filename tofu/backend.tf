# Run `tofu/bootstrap` first, then fill in the bucket name from its output.
terraform {
  backend "s3" {
    bucket       = "bedrockconnect-tofu-state"
    key          = "bedrockconnect/tofu.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
