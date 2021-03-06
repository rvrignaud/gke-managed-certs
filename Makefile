all: gofmt build-binary-in-docker run-test-in-docker clean cross

TAG?=dev
REGISTRY?=eu.gcr.io/managed-certs-gke
KUBECONFIG?=${HOME}/.kube/config
KUBERNETES_PROVIDER?=gke

name=managed-certificate-controller
runner_image=${name}-runner
runner_path=/gopath/src/github.com/GoogleCloudPlatform/gke-managed-certs/
gcloud_sdk_root=`gcloud info --format="value(installation.sdk_root)"`
gcloud_config_dir=`gcloud info --format="value(config.paths.global_config_dir)"`

auth-configure-docker:
	test -f /etc/service-account/service-account.json && \
		gcloud auth activate-service-account --key-file=/etc/service-account/service-account.json && \
		gcloud auth configure-docker || true

# Builds the managed certs controller binary
build-binary: clean deps
	godep go build -o ${name}

# Builds the managed certs controller binary using a docker runner image
build-binary-in-docker: docker-runner-builder
	docker run -v `pwd`:${runner_path} ${runner_image}:latest bash -c 'cd ${runner_path} && make build-binary'

clean:
	rm -f ${name}

# Checks if Google criteria for releasing code as OSS are met
cross:
	/google/data/ro/teams/opensource/cross .

deps:
	go get github.com/tools/godep

# Builds and pushes a docker image with managed certs controller binary
docker: auth-configure-docker
	docker build --pull -t ${REGISTRY}/${name}:${TAG} .
	docker push ${REGISTRY}/${name}:${TAG}

# Builds a runner image, i. e. an image used to build a managed-certificate-controller binary and to run its tests.
docker-runner-builder:
	docker build -t ${runner_image} runner

e2e:
	KUBECONFIG=${KUBECONFIG} \
	KUBERNETES_PROVIDER=${KUBERNETES_PROVIDER} \
	godep go test ./e2e/... -v -test.timeout=60m

# Formats go source code with gofmt
gofmt:
	gofmt -w main.go
	find . -mindepth 1 -maxdepth 1 -name Godeps -o -name vendor -prune -o -type d -print | xargs gofmt -w

# Builds the managed certs controller binary, then a docker image with this binary, and pushes the image, for dev
release: release-ci clean

# Builds the managed certs controller binary, then a docker image with this binary, and pushes the image, for continuous integration
release-ci: build-binary-in-docker run-test-in-docker docker
	make -C http-hello

run-e2e-in-docker: docker-runner-builder auth-configure-docker
	docker run -v `pwd`:${runner_path} \
		-v ${gcloud_sdk_root}:${gcloud_sdk_root} \
		-v ${gcloud_config_dir}:/root/.config/gcloud \
		-v ${KUBECONFIG}:/root/.kube/config \
		${runner_image}:latest bash -c 'cd ${runner_path} && make e2e'

run-test-in-docker: docker-runner-builder
	docker run -v `pwd`:${runner_path} ${runner_image}:latest bash -c 'cd ${runner_path} && make test'

test:
	godep go test ./pkg/... -cover

.PHONY: all auth-configure-docker build-binary build-binary-in-docker build-dev clean cross deps docker docker-runner-builder e2e release release-ci run-e2e-in-docker run-test-in-docker test
