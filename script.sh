#!/usr/bin/env bash

########################################################################
# Minimum resources required for the script to function
########################################################################
# Path script source
PATH_FULL=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
cd $PATH_FULL/
# Reads the configuration file
[ ! -e "${PATH_FULL}/conf.ini" ] && { echo "*** ERRO ***: conf.ini file not found. Rename conf.ini.dist to conf.ini."; exit 1; }
source "${PATH_FULL}/conf.ini"
# Adds base functions
[ ! -e "${PATH_FULL}/extra/base.sh" ] && { echo "*** ERRO ***: File extra/base.sh not located. Required to proceed with the script."; exit 1; }
source "${PATH_FULL}/extra/base.sh"
# Generates the program's PID and creates the lock file
PIDFILE="/tmp/$(basename $0).pid"
LOCKFILE="/tmp/$(basename $0).lock"
LOCKFD=99
_lock()             { flock -$1 $LOCKFD; }
_no_more_locking()  { _lock u; _lock xn && rm -f ${LOCKFILE} && rm -r ${PIDFILE}; }
_prepare_locking()  { eval "exec ${LOCKFD}>\"${LOCKFILE}\""; trap _no_more_locking EXIT; }
_prepare_locking
_lock xn || { Messages -E "Program $(basename $0) already running. PID: $(cat ${PIDFILE}). Lock: ${LOCKFILE}"; exit 1 ; }
echo $$ > ${PIDFILE}
########################################################################

function DATESTAMP(){ date +"%Y%m%d-%H%M" ;}
function DATESTAMPHUMAN() { date +"%Y/%m/%d - %H:%M:%S" ;}

[ -d ${LOG_PATH} ] || mkdir -p ${LOG_PATH}

clear
echo
Messages "-------------------------------------------------------------------------------"
Messages "--> $(DATESTAMPHUMAN)"
Messages "--> Starting script"
Messages "-------------------------------------------------------------------------------"
echo

# Retrieves the domains to be updated in OCI.
[[ $(ls domains/*.conf 2>/dev/null) ]] || {
  Messages -E "No files found in domains/*.conf."
  exit 1
}

echo

Messages -I "Retrieving the domain configuration files."
error_localfile=false
for i in $(ls domains/*.conf)
do
  echo
  Messages -L "Analyzing file: $i"
  source "$i"

  sleep 1
  # Data for OCI - LB Listener
  Messages -I "--> Data for OCI - LB Listener:"
  Messages -I "Domain     -> $DOMAIN"
  Messages -I "Listener   -> $LISTENER"
  Messages -I "Backend    -> $LISTENER_BACKEND"
  Messages -I "Hostnames  -> $LISTENER_HOSTNAMES"
  Messages -I "Protocol   -> $LISTENER_PROTOCOL"
  Messages -I "Port       -> $LISTENER_PORT"
  Messages -I "Cipher     -> $LISTENER_CIPHER"

  sleep 1
  # Data for LetsEncrypt
  Messages -I "--> Data for local LetsEncrypt:"
  CERT_NAME="LetsEncrypt_${DOMAIN}"
  CERT_PATH="${LETSENCRYPT_PATH}/${DOMAIN}"
  CERT_CA="${CERT_PATH}/chain.pem"
  CERT_PUBLIC="${CERT_PATH}/cert.pem"
  CERT_PRIVATE="${CERT_PATH}/privkey.pem"

  Messages -L "Locating certificates in ${CERT_PATH}/"
  [ -e ${CERT_CA} ]      && { Messages -S "CA         -> ${CERT_CA}"      ; } || { Messages -E "CA not found -> ${CERT_CA}"           ; error_localfile=true ; }
  [ -e ${CERT_PUBLIC} ]  && { Messages -S "Public     -> ${CERT_PUBLIC}"  ; } || { Messages -E "Public not found -> ${CERT_PUBLIC}"   ; error_localfile=true ; }
  [ -e ${CERT_PRIVATE} ] && { Messages -S "Private    -> ${CERT_PRIVATE}" ; } || { Messages -E "Private not found -> ${CERT_PRIVATE}" ; error_localfile=true ; }

  if [ $error_localfile = true ]
  then
    Messages -C "Procedure for the domain $DOMAIN not carried out. There are errors in the LetsEncrypt files"
    error_localfile=false
    continue
  fi

  # Comparing the local certificate with the published certificate
  function getCurrentCertPublished(){
    export cert_temp="/tmp/cert.pem"
    openssl s_client -connect $DOMAIN:443 </dev/null 2>/dev/null | openssl x509 -outform PEM > ${cert_temp}
  }

  function testURLDomainResponse(){
    curl -Is --insecure https://${DOMAIN} > /dev/null 2> /dev/null; echo $?
  }

  echo
  sleep 1
  Messages -L "Comparing the local certificate with the published certificate"
  Messages -L "Testing HTTPS response from the domain ${DOMAIN}"
  [ $(testURLDomainResponse) -eq 0 ] && { Messages -S "Response from the domain ${DOMAIN}" ; } || { Messages -E "Failure in communication with the domain ${DOMAIN}"; continue ; }
  Messages -L "Retrieving the published digital certificate"
  getCurrentCertPublished
  Messages -L "Checking the file content type ${cert_temp}"
  if file ${cert_temp} | grep "PEM certificate" > /dev/null
  then
    Messages -S "Certificate of type: PEM certificate"
  else
    Messages -E "File different from PEM certificate type"
    continue
  fi
  Messages -L "Comparing the certificates"
  if cmp -s ${CERT_PUBLIC} ${cert_temp}
  then
    Messages -S "The certificates are identical, no action taken."
    continue
  else
    Messages -I "The certificates are different, updated certificate on the LB."
  fi

  echo
  Messages -A "Renewing the certificate in OCI"
  Messages -L "Validating access in OCI"
  function testOCIAccess(){
    $oci lb certificate list --load-balancer-id ${OCID_LB} > /dev/null 2>> ${LOG_PATH}/oci.error.log; echo $?
  }
  [ $(testOCIAccess) -eq 0 ] && {
    Messages -S "Access successful"
  } || {
    Messages -E "Access to OCI failed, process terminated"
    continue
  }

  sleep 1

  # Preparing the name of the new certificate
  CERT2ADD="${CERT_NAME}_$(date +%y%m%d)"
  Messages -I "Name of the new certificate to be added --> ${CERT2ADD}"

  # Retrieving the certificate name in OCI
  function getOCICurrentCertName(){
    $oci lb certificate list --load-balancer-id ${OCID_LB} | grep ${CERT_NAME} | tr -d '[:blank:]' | sed 's/^\"certificate-name\":\"//' | sed 's/\"\,$//'
  }
  [ -z $(getOCICurrentCertName) ] && {
    Messages -E "certificate ${CERT_NAME} not found in OCI. Procedure terminated"
    continue
  }

  CERT2DELETE=$(getOCICurrentCertName)
  Messages -I "Name of the certificate to be deleted   --> ${CERT2DELETE}"



  # Adding the new certificate
  # ------------------------------------------------------------------------------------------
  Messages -L "Adding the new certificate to OCI"
  sleep 1
  function certOCIAdd(){
    $oci lb certificate create \
      --load-balancer-id ${OCID_LB} \
      --certificate-name ${CERT2ADD} \
      --public-certificate-file ${CERT_PUBLIC} \
      --private-key-file ${CERT_PRIVATE} \
      --ca-certificate-file ${CERT_CA} >> ${LOG_PATH}/oci.log 2>> ${LOG_PATH}/oci.error.log; echo $?
  }
  if [ $(certOCIAdd) -eq 0 ]
  then
    Messages -S "Certificate successfully added"
  else
    Messages -E "Failed to add the certificate ${CERT2ADD} to OCI. Process terminated"
    continue
  fi

  Messages -L "Waiting a few seconds for publication..."
  sleep 30
  Messages -L "Continuing"



  # Adjusting the listener for the new certificate
  # ------------------------------------------------------------------------------------------
  Messages -L "Updating the Listener in OCI for the new certificate"
  sleep 1
  function listenerUpdate(){
    $oci lb listener update \
      --load-balancer-id ${OCID_LB} \
      --force \
      --listener-name ${LISTENER} \
      --protocol ${LISTENER_PROTOCOL} \
      --port ${LISTENER_PORT} \
      --ssl-certificate-name ${CERT2ADD} \
      --default-backend-set-name "${LISTENER_BACKEND}" \
      --cipher-suite-name ${LISTENER_CIPHER} \
      --hostname-names ${LISTENER_HOSTNAMES} >> ${LOG_PATH}/oci.log 2>> ${LOG_PATH}/oci.error.log; echo $?
  }

  if [ $(listenerUpdate) -eq 0 ]
  then
    Messages -S "Listerner successfully updated"
  else
    Messages -E "Failed to update the Listerner ${LISTENER} in OCI. Process terminated"
    continue
  fi
  
  Messages -L "Waiting a few seconds for publication..."
  sleep 30
  Messages -L "Continuing"



  # Adjusting the Backends
  # ------------------------------------------------------------------------------------------
  function backendSetUpdate(){
    $oci lb backend-set update \
    --force \
    --load-balancer-id ${OCID_LB} \
    --backend-set-name ${BACKENDSET_NAME} \
    --policy ${BACKENDSET_POLICY} \
    --backends="${BACKENDSET_BACKENDS}" \
    --health-checker-protocol ${BACKENDSET_HEALTH_CHECKER_PROTOCOL} \
    --health-checker-url-path ${BACKENDSET_HEALTH_CHECKER_URL_PATH} \
    --ssl-certificate-name="${CERT2ADD}" >> ${LOG_PATH}/oci.log 2>> ${LOG_PATH}/oci.error.log; echo $?
  }

  if [ ! -z ${BACKENDSET_NAME} ]
  then
    Messages -L "Updating the backend-set ${BACKENDSET_NAME} in OCI"

    if [ $(backendSetUpdate) ]
    then
      Messages -S "Backend-set successfully updated"
    else
      Messages -E "Failed to update the backend-set ${BACKENDSET_NAME} in OCI. Process terminated"
      continue
    fi
  fi

  Messages -L "Waiting a few second for publication..."
  sleep 30
  Messages -L "Continuing"



  # Removing the old certificate
  # ------------------------------------------------------------------------------------------
  Messages -A "Removing the old certificate"
  sleep 1
  function removeOldCert(){
    $oci lb certificate delete \
      --force \
      --load-balancer-id ${OCID_LB} \
      --certificate-name ${CERT2DELETE} >> ${LOG_PATH}/oci.log 2>> ${LOG_PATH}/oci.error.log; echo $?
  }
  if [ $(removeOldCert) -eq 0 ]
  then
    Messages -S "Certificate successfully removed"
  else
    Messages -E "Failed to remove the certificate ${CERT2DELETE} in OCI. Process terminated"
    continue
  fi

  echo
  echo
done

exit 0
