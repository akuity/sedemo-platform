# release-infra

A standalone OpenTofu example: no backend, no cloud credentials, one provider
(`hashicorp/random`). `tofu apply -var release=<tag>` emits a word-pair release
string that is a pure function of the input, so the same input always gives the
same string.

    tofu init && tofu apply -auto-approve -var release=abc1234
    tofu output release_message      # -> zephyr-amber-36f5

**Not wired into any promotion.** It used to run inside the `render` task and
patch its output onto the Deployment as `SMOL_MESSAGE`; that was removed because
it did not read clearly in a demo. `SMOL_MESSAGE` is now plain committed YAML in
each `stages/<stage>/release-message.yaml`. Kept here to demo Kargo's `tf-apply`
and `tf-output` steps on their own.
