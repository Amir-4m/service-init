#!/bin/bash

PROJECT_NAME="$1"
PROJECT_GIT_URL="$2"
OWNER_USER="$3"

if [ -z "$PROJECT_NAME" ]; then
	echo "Project name is required !"
	exit 1
fi

if [ -z "$PROJECT_GIT_URL" ]; then
	echo "Project git url is required !"
	exit 1
fi

echo "creating neccessary directories ..."

PROJECT_DIR="/var/www/$PROJECT_NAME"

# create neccessary directories
mkdir -p "$PROJECT_DIR" && mkdir -p "$PROJECT_DIR"/confs
cp .coveragerc "$PROJECT_DIR"/project
virtualenv --prompt="($PROJECT_NAME) " -q "$PROJECT_DIR"/venv
virtualenv --relocatable "$PROJECT_DIR"/venv
source "$PROJECT_DIR"/venv/bin/activate

echo "Enter git branch name?"
read gitbranch

git clone -b "$gitbranch" "$PROJECT_GIT_URL" "$PROJECT_DIR"/project

# set nginx
echo "Do you wish to set nginx for $PROJECT_NAME ? (y/n)"
read ngyn
if [[ ($ngyn == "y" || $ngyn == "") ]]; then
echo "setting nginx configurations ..."
sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g" nginx-template.conf > $PROJECT_DIR/confs/nginx.conf
ln -s $PROJECT_DIR/confs/nginx.conf /etc/nginx/sites-available/$PROJECT_NAME.conf
ln -s /etc/nginx/sites-available/$PROJECT_NAME.conf /etc/nginx/sites-enabled/$PROJECT_NAME.conf
nginx -t
service nginx restart
fi

#set uwsgi
echo "Do you wish to set uwsgi for $PROJECT_NAME ? (y/n)"
read uwyn
if [[ ($uwyn == "y" || $btyn == "") ]]; then
echo "setting uwsgi configurations ..."
echo "How many workers do you wish to set for uwsgi $PROJECT_NAME ?"
read WORKER_PROCESSES
sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g" -e "s/\$OWNER_USER/$OWNER_USER/g" -e "s/\$WORKER_PROCESSES/$WORKER_PROCESSES/g" uwsgi-template.ini > $PROJECT_DIR/confs/uwsgi.ini
ln -s $PROJECT_DIR/confs/uwsgi.ini /etc/uwsgi/vassals/$PROJECT_NAME.ini
fi

#set supervisor
echo "Do you wish to set supervisor for $PROJECT_NAME ? (y/n)"
read spyn
if [[ ($spyn == "y" || $spyn == "") ]]; then
	echo "setting supervisor configurations ..."
	echo "Do you have beat for $PROJECT_NAME ? (y/n)"
	read btyn
	echo "setting worker and beat configurations ..."
	echo "[group:$PROJECT_NAME]
programs=$PROJECT_NAME-beat,$PROJECT_NAME-worker" >> $PROJECT_DIR/confs/supervisor.conf

	sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g -e "s/\$OWNER_USER/$OWNER_USER/g""  supervisor-worker-template.conf >> $PROJECT_DIR/confs/supervisor.conf
	
	if [[ ($btyn == "y" || $btyn == "") ]]; then
		sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g -e "s/\$OWNER_USER/$OWNER_USER/g""  supervisor-beat-template.conf >> $PROJECT_DIR/confs/supervisor.conf	
	fi

	ln -s $PROJECT_DIR/confs/supervisor.conf /etc/supervisor/conf.d/$PROJECT_NAME.conf
		
	supervisorctl reread
	supervisorctl update

fi

if [ ! -z "$OWNER_USER" ]; then
	echo "Changing the owner of $PROJECT_DIR to $OWNER_USER"
	chown -R $OWNER_USER: $PROJECT_DIR
fi


echo "creating develop database ..."
echo "enter maintainer users: "
read DB_MAINTAINERS
su - postgres <<EOF
psql postgres -c "CREATE DATABASE ${PROJECT_NAME}_dev WITH ENCODING 'UTF8'"
psql postgres -c "grant all privileges on database ${PROJECT_NAME}_dev to ${DB_MAINTAINERS},$OWNER_USER;"

echo "creating main database ..."
psql postgres -c "CREATE DATABASE ${PROJECT_NAME} WITH ENCODING 'UTF8'"
psql postgres -c "grant all privileges on database $PROJECT_NAME to $OWNER_USER;"

EOF
echo "done"

if [[ ($spyn == "y" || $spyn == "") ]]; then
	echo "creating develop broker vhost ..."
	echo "enter maintainer user: "
	read BR_MAINTAINER
	
	rabbitmqctl add_vhost "${PROJECT_NAME}_dev"
	rabbitmqctl set_permissions -p "${PROJECT_NAME}_dev" "$BR_MAINTAINER" ".*" ".*" ".*"
	rabbitmqctl set_permissions -p "${PROJECT_NAME}_dev" "$OWNER_USER" ".*" ".*" ".*"

	echo "creating main broker vhost ..."
	rabbitmqctl add_vhost "${PROJECT_NAME}"
	rabbitmqctl set_permissions -p "${PROJECT_NAME}" "$OWNER_USER" ".*" ".*" ".*"
fi

echo "All Done!"



