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

if ! [[ $PROJECT_GIT_URL =~ ^https://. ]]; then
        echo "Enter git ssh key file address: "
        read GIT_SSH_FILE
	GIT_SSH="ssh -i $GIT_SSH_FILE"
fi

echo "$PROJECT_NAME"
echo "creating neccessary directories ..."

PROJECT_DIR="/var/www/$PROJECT_NAME"

# create neccessary directories
mkdir -p "$PROJECT_DIR" && mkdir -p "$PROJECT_DIR"/confs
virtualenv --prompt="($PROJECT_NAME)" -q "$PROJECT_DIR"/venv
virtualenv --relocatable "$PROJECT_DIR"/venv
source "$PROJECT_DIR"/venv/bin/activate

# clone project
echo "Enter git branch name?"
read gitbranch
if [ -z "$GIT_SSH" ]; then
        git clone -b "$gitbranch" "$PROJECT_GIT_URL" "$PROJECT_DIR"/project
elif [ ! -z "$GIT_SSH" ]; then
	"$GIT_SSH"  git clone -b "$gitbranch" "$PROJECT_GIT_URL" "$PROJECT_DIR"/project
fi

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
sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g" -e "s/\$WORKER_PROCESSES/$WORKER_PROCESSES/g" uwsgi-template.ini > $PROJECT_DIR/confs/uwsgi.ini
ln -s $PROJECT_DIR/confs/uwsgi.ini /etc/uwsgi/vassals/$PROJECT_NAME.ini
fi

#set supervisor
echo "Do you wish to set supervisor for $PROJECT_NAME ? (y/n)"
read spyn
if [[ ($spyn == "y" || $btyn == "") ]]; then
	echo "setting supervisor configurations ..."
	echo "Do you have beat for $PROJECT_NAME ? (y/n)"
	read btyn
	
	echo "Do you have worker for $PROJECT_NAME ? (y/n)"
	read wryn

	if [[ (($btyn == "y" || $btyn == "") && ($wryn == "y" || $wryn == "")) ]]; then
		echo "setting worker and beat configurations ..."
		echo "[group:$PROJECT_NAME]
		programs=$PROJECT_NAME-beat,$PROJECT_NAME-worker" >> $PROJECT_DIR/confs/supervisor.conf
		sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g"  supervisor-beat-template.conf >> $PROJECT_DIR/confs/supervisor.conf	
		sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g"  supervisor-worker-template.conf >> $PROJECT_DIR/confs/supervisor.conf
		ln -s $PROJECT_DIR/confs/supervisor.conf /etc/supervisor/conf.d/$PROJECT_NAME.conf

	elif [[ (($btyn == "y" || $btyn == "") && ($wryn == "n")) ]]; then
		echo "setting beat configurations ..."
		echo "[group:$PROJECT_NAME]
		programs=$PROJECT_NAME-beat" >> $PROJECT_DIR/confs/supervisor.conf
		sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g"  supervisor-beat-template.conf >> $PROJECT_DIR/confs/supervisor.conf
		ln -s $PROJECT_DIR/confs/supervisor.conf /etc/supervisor/conf.d/$PROJECT_NAME.conf

	elif [[ (($wryn == "y" || $wryn == "") && ($btyn == "n")) ]]; then
	        echo "setting worker configurations ..."
        	echo "[group:$PROJECT_NAME]
		programs=$PROJECT_NAME-worker" >> $PROJECT_DIR/confs/supervisor.conf
		sed -e "s/\$PROJECT_NAME/$PROJECT_NAME/g"  supervisor-worker-template.conf >> $PROJECT_DIR/confs/supervisor.conf
		ln -s $PROJECT_DIR/confs/supervisor.conf /etc/supervisor/conf.d/$PROJECT_NAME.conf

	else
		echo "setting supervisor canceled!"
	fi

	supervisorctl reread
	supervisorctl update

fi

if [ ! -z "$OWNER_USER" ]; then
	echo "Changing the owner of $PROJECT_DIR to $OWNER_USER"
	chown -R $OWNER_USER $PROJECT_DIR
fi

