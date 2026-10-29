# shellcheck shell=bash
# app.sh - management scripts for the production docker compose project

# create_app_scripts - install app-* scripts into /usr/local/bin.
# Values like ${APP_DIR} are substituted NOW (at setup time), so the
# installed scripts contain fixed paths and take no arguments
create_app_scripts(){
    local compose="docker compose -f ${APP_DIR}/${COMPOSE_FILE} --project-directory ${APP_DIR}"
    
    create_script app-start "${compose} up -d"
    create_script app-stop "${compose} stop"
    create_script app-restart "${compose} restart"
    create_script app-status "${compose} ps"
    create_script app-logs "${compose} logs --tail=200"
    
    # Update code, rebuild images, recreate containers, run migrations, rebuild caches
    create_script app-deploy "cd ${APP_DIR}
if [ -f .env ]; then chmod 600 .env; fi
git pull --ff-only
${compose} build
${compose} up -d --wait --remove-orphans
${compose} exec -T ${APP_SERVICE} php artisan migrate --force
${compose} exec -T ${APP_SERVICE} php artisan optimize"
}