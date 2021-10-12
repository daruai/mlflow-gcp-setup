CLOUD_SQL_PASS=$1

PROJECT_ID=$(gcloud config get-value project)
RANDOM_ID=$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2}')

# Building mlflow image
docker build -t mlflow:1.14.1 .

# Service account
gcloud iam service-accounts create mlflow-tracking-sa \
    --description="Service Account to run the MLFLow tracking server" \
    --display-name="MLFlow tracking SA"

# Bucket
BUCKET_NAME=gs://$PROJECT_ID-mlflow-$RANDOM_ID
gsutil mb $BUCKET_NAME

# Cloud SQL
SQL_NAME=mlflow-backend-$RANDOM_ID
gcloud sql instances create $SQL_NAME --tier=db-f1-micro --region=us-central1 \
    --root-password=$CLOUD_SQL_PASS \
    --storage-type=SSD --async
PENDING_OPERATIONS=$(gcloud sql operations list --instance=$SQL_NAME --filter='status!=DONE' --format='value(name)')
gcloud sql operations wait "${PENDING_OPERATIONS}" --timeout=unlimited

# Service account permissions
gsutil iam ch 'serviceAccount:mlflow-tracking-sa@$PROJECT_ID.iam.gserviceaccount.com:roles/storage.admin' $BUCKET_NAME
gcloud project add-iam-policy-binding $PROJECT_ID \
    --member='serviceAccount:mlflow-tracking-sa@$PROJECT_ID.iam.gserviceaccount.com' \
    --role=roles/cloudsql.editor

# Filling placeholders in startup script
sed -i 's/<PROJECT-ID>/'$PROJECT_ID'/' start_mlflow_tracking.sh
sed -i 's/<BUCKET-NAME>/'$BUCKET_NAME'/' start_mlflow_tracking.sh
sed -i 's/<YOUR_ROOT_PASSWORD>/'$CLOUD_SQL_PASS'/' start_mlflow_tracking.sh
sed -i 's/<SQL-NAME>/'$SQL_NAME'/' start_mlflow_tracking.sh
# Moving startup script to bucket
gsutil cp start_mlflow_tracking.sh $BUCKET_NAME/scripts/start_mlflow_tracking.sh

# Compute engine
gcloud beta compute --project=$PROJECT_ID instances create mlflow-tracking-server --zone=us-central1-a \
    --machine-type=e2-medium --subnet=default --network-tier=PREMIUM \
    --metadata=startup-script-url=$BUCKET_NAME/scripts/start_mlflow_tracking.sh --maintenance-policy=MIGRATE \
    --service-account=mlflow-tracking-sa@$PROJECT_ID.iam.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/cloud-platform --tags=mlflow-tracking-server \
    --image=cos-77-12371-1109-0 --image-project=cos-cloud --boot-disk-size=10GB --boot-disk-type=pd-balanced \
    --boot-disk-device-name=mlflow-tracking-server --no-shielded-secure-boot --shielded-vtpm \
    --shielded-integrity-monitoring --reservation-affinity=any

# Firewall
gcloud compute firewall-rules create allow-mlflow-tracking --network default --priority 1000 \
    --direction ingress --action allow --target-tags mlflow-tracking-server \
    --source-ranges 0.0.0.0/0 --rules tcp:5000 --enable-logging