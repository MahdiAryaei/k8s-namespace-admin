#!/bin/bash

# before do this create user in your host

read -p "Enter username : " username
read -p "Enter namespace (must be created befor run this script) : " namespace

csr=$(kubectl get csr | grep ${username}) > /dev/null

test -f /home/$username/.kube/config

if [[ $? -ne 0 ]];then

################# create user kube-config file #####################
echo $username
group=$username
openssl genrsa -out ${username}.key 2048
openssl req -new -key ${username}.key -out ${username}.csr -subj "/CN=${username}/O=${group}"

csrbase64=`cat ${username}.csr | base64 | tr -d "\n"`

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $username
spec:
  request: $csrbase64
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

kubectl certificate approve $username
kubectl get csr $username -o jsonpath='{.status.certificate}'| base64 -d > ${username}.crt

chown $username: $username.*

sudo -u $username kubectl config set-cluster cluster.local --server=https://127.0.0.1:6443 --certificate-authority /etc/kubernetes/pki/ca.crt --embed-certs
sudo -u $username kubectl config set-credentials $username --client-key=${username}.key --client-certificate=${username}.crt --embed-certs=true
sudo -u $username kubectl config set-context $username --cluster=cluster.local --user=$username
sudo -u $username kubectl config use-context $username

rm $username.*

else
  echo "/home/$username/.kube/config does exist"
fi

################# make user admin of a namespace#####################
# bind cluser-admin role to user was created.Use namespace to limit
# user to specific namespace that you want.

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: mycluster-$namespace-admin-$username
  namespace: $namespace
subjects:
# You can specify more than one "subject"
- kind: User
  name: $username # "name" is case sensitive
  apiGroup: rbac.authorization.k8s.io
roleRef:
  # "roleRef" specifies the binding to a Role / ClusterRole
  kind: ClusterRole #this must be Role or ClusterRole
  name: cluster-admin # this must match the name of the Role or ClusterRole you wish to bind to
  apiGroup: rbac.authorization.k8s.io
EOF

echo "$username is now admin of $namespace namespace"
echo "run \"kubectl get -n $namespace pods\" as $username user to sure everything is Ok ! "
