#!/bin/bash

PROJECT_NAME="$1"
PROJECT_GIT_URL="$2"
OWNER_USER="$3"

randomPassword()
{ 
	        </dev/urandom tr -dc '12345!@#$%qwertQWERTasdfgASDFGzxcvbZXCVB' | head -c8; echo ""
		        }


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
virtualenv --prompt="($PROJECT_NAME) " -q "$PROJECT_DIR"/venv
virtualenv --relocatable "$PROJECT_DIR"/venv
source "$PROJECT_DIR"/venv/bin/activate

echo "Enter git branch name?"
read gitbranch

git clone -b "$gitbranch" "$PROJECT_GIT_URL" "$PROJECT_DIR"/project
cp .coveragerc "$PROJECT_DIR"/project/.coveragerc

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


echo "creating main database ..."
echo "enter [user] [host] [port]: "
  
read DB_HOST_USER HOST PORT
DB_USER_CREATE=${PROJECT_NAME}_user$(awk -v min=1 -v max=1000 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
DB_USER_CREATE_PASSWORD=$(randomPassword)
sudo psql -U "$DB_HOST_USER" -h "$HOST" -p "$PORT" -W <<EOF
CREATE DATABASE $PROJECT_NAME WITH ENCODING 'UTF8';
CREATE USER $DB_USER_CREATE WITH PASSWORD '$DB_USER_CREATE_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE $PROJECT_NAME TO $DB_USER_CREATE;


EOF
echo "USER OF THE DATABASE $PROJECT_NAME IS $DB_USER_CREATE WITH PASSWORD $DB_USER_CREATE_PASSWORD"
echo "DB_USER=$DB_USER_CREATE
DB_PASSWORD=$DB_USER_CREATE_PASSWORD" >> $PROJECT_DIR/project/.env
echo "done"

if [[ ($spyn == "y" || $spyn == "") ]]; then
	echo "creating broker vhost ..."
	echo "enter [username] [password] [host] [port]: "
	read RBMQ_USERNAME RBMQ_PASSWORD RBMQ_HOST RBMQ_PORT
	RBMQ_USER_CREATE=${PROJECT_NAME}_user$(awk -v min=1 -v max=1000 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
	RBMQ_USER_CREATE_PASSWORD=$(randomPassword)
	curl -u "$RBMQ_USERNAME":"$RBMQ_PASSWORD" -X PUT http://"$RBMQ_HOST":"$RBMQ_PORT"/api/vhosts/"$PROJECT_NAME"

	
	curl -i -u "$RBMQ_USERNAME":"$RBMQ_PASSWORD" -H "content-type:application/json"     -XPUT -d'{"password":"'$RBMQ_USER_CREATE_PASSWORD'","tags":"monitoring"}'     http://"$RBMQ_HOST":"$RBMQ_PORT"/api/users/"$RBMQ_USER_CREATE"
        curl -i -u "$RBMQ_USERNAME":"$RBMQ_PASSWORD" -H "content-type:application/json"     -XPUT -d'{"configure":".*","write":".*","read":".*"}'     http://"$RBMQ_HOST":"$RBMQ_PORT"/api/permissions/"$PROJECT_NAME"/"$RBMQ_USER_CREATE"

	echo "USER OF THE RBMQ $PROJECT_NAME IS $RBMQ_USER_CREATE WITH PASSWORD $RBMQ_USER_CREATE_PASSWORD"

	echo "RBMQ_USER=$RBMQ_USER_CREATE
RBMQ_PASSWORD=$RBMQ_USER_CREATE_PASSWORD" >> $PROJECT_DIR/project/.env

fi

echo "All Done!"



