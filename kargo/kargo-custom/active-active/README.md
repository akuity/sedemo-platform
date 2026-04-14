# Rollouts Demo

Simple demo with Rollouts enabled application, deploying to multiple prod regions. (actually just namespaces)

- Uses prometheus based AnalysisTemplate for 200 vs 500 response rates
- Uses PR-based approval for prod deployment


## Story Telling

- You can pull up rollouts dashboard in ArgoCD ui to see canary progessive delivery
- You can open the app itself and adjust the error slider to cause a rollout to fail.


## URLS

- prometheus.akpdemoapps.link
  - [dev graph](http://prometheus.akpdemoapps.link/query?g0.expr=%28+sum%28rate%28nginx_ingress_controller_requests%7Bnamespace%3D%22demo-dev%22%2Cstatus%3D%22200%22%2Ccanary%3D%22demo-dev-rollouts-svc-canary-80%22%7D%5B30s%5D%29%29+%2B+1+%29%0A%2F%0A%28+sum%28rate%28nginx_ingress_controller_requests%7Bnamespace%3D%22demo-dev%22%2Ccanary%3D%22demo-dev-rollouts-svc-canary-80%22%7D%5B30s%5D%29%29+%2B+1+%29&g0.show_tree=0&g0.tab=graph&g0.range_input=1h&g0.res_type=auto&g0.res_density=medium&g0.display_mode=lines&g0.show_exemplars=0)
  - [staging graph](
  - [dev graph](http://prometheus.akpdemoapps.link/query?g0.expr=%28+sum%28rate%28nginx_ingress_controller_requests%7Bnamespace%3D%22demo-staging%22%2Cstatus%3D%22200%22%2Ccanary%3D%22demo-staging-rollouts-svc-canary-80%22%7D%5B30s%5D%29%29+%2B+1+%29%0A%2F%0A%28+sum%28rate%28nginx_ingress_controller_requests%7Bnamespace%3D%22demo-staging%22%2Ccanary%3D%22demo-staging-rollouts-svc-canary-80%22%7D%5B30s%5D%29%29+%2B+1+%29&g0.show_tree=0&g0.tab=graph&g0.range_input=1h&g0.res_type=auto&g0.res_density=medium&g0.display_mode=lines&g0.show_exemplars=0)

- demo-dev.akpdemoapps.link
- demo-staging.akpdemoapps.link
- demo-prod-emea.akpdemoapps.link
- demo-prod-amer-west.akpdemoapps.link
- demo-prod-amer-east.akpdemoapps.link
