# pālana — fixture and verification sugar. The verification stack itself
# is pre-commit + CI; these targets are the operator's shorthand.

.PHONY: verify coverage sshd-fixture sshd-fixture-stop zfs-fixture zfs-fixture-destroy

verify:
	swift-format lint --recursive --strict Sources Tests
	swiftlint lint --strict --quiet
	swift build
	swift test

coverage:
	swift test --enable-code-coverage
	scripts/coverage-floor.sh 90

sshd-fixture:
	scripts/sshd-fixture.sh start

sshd-fixture-stop:
	scripts/sshd-fixture.sh stop

zfs-fixture:
	scripts/zfs-fixture.sh start

zfs-fixture-destroy:
	scripts/zfs-fixture.sh destroy
