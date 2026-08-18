# -include, not include: a fresh checkout has no .env yet, and `make setup`
# is how you create one. A plain `include` fails hard on a missing file,
# which would make `make setup` unable to run on the very first checkout.
-include .env
export

LIB_DIR := ../../lib

.PHONY: setup up down logs backup restore update status

# Interactive by default. For scripted/customized use:
#   make setup ARGS="--set GAME_PORT=16265 --set MEMORY=8192m --yes"
# See ./setup.sh --help for all options.
setup:
	@./setup.sh $(ARGS)

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f --tail=200

status:
	docker compose ps

backup:
	$(LIB_DIR)/backup.sh $(GAME_NAME) $(DATA_DIR)

restore:
	$(LIB_DIR)/restore.sh $(GAME_NAME) $(DATA_DIR)

# snapshot, pull the pinned tag, recreate, health check.
# rollback: edit IMAGE_TAG in .env back to the old value, `make update`
# again, and `make restore` too if the bad version wrote data you don't want.
#
# Wait loop is longer than the template default (60 x 10s = 10 minutes,
# not 10 x 5s = 50s): Zomboid's JVM boot is commonly 1-3+ minutes even
# without mods, so the template's default would report a false timeout
# on every deploy.
update:
	@echo "==> [$(GAME_NAME)] snapshotting before update"
	$(MAKE) backup
	@echo "==> [$(GAME_NAME)] pulling $(IMAGE_TAG)"
	docker compose pull
	@echo "==> [$(GAME_NAME)] recreating container"
	docker compose up -d --force-recreate
	@echo "==> [$(GAME_NAME)] waiting for health check (can take several minutes)"
	@i=0; \
	while [ $$i -lt 60 ]; do \
		status=$$(docker inspect --format='{{.State.Health.Status}}' $$(docker compose ps -q game) 2>/dev/null || echo "unknown"); \
		if [ "$$status" = "healthy" ]; then echo "==> [$(GAME_NAME)] healthy"; exit 0; fi; \
		if [ "$$status" = "unhealthy" ]; then \
			echo "==> [$(GAME_NAME)] unhealthy after update."; \
			echo "    rollback: set IMAGE_TAG back in .env, then 'make update', then 'make restore' if data changed."; \
			exit 1; \
		fi; \
		i=$$((i + 1)); \
		sleep 10; \
	done; \
	echo "==> [$(GAME_NAME)] health check timed out, check manually with 'make logs'"; \
	exit 1
