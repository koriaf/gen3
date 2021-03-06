#!/bin/bash

if [[ -n "${GENERATION_DEBUG}" ]]; then set ${GENERATION_DEBUG}; fi
trap '. ${GENERATION_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

# Defaults
STACK_INITIATE_DEFAULT="true"
STACK_MONITOR_DEFAULT="true"
STACK_OPERATION_DEFAULT="update"
STACK_WAIT_DEFAULT=30

function usage() {
    cat <<EOF

Manage a CloudFormation stack

Usage: $(basename $0) -t TYPE -u DEPLOYMENT_UNIT -i -m -w STACK_WAIT -r REGION -n STACK_NAME -y -d

where

(o) -d (STACK_OPERATION=delete) to delete the stack
    -h                          shows this text
(o) -i (STACK_MONITOR=false)    initiates but does not monitor the stack operation
(o) -m (STACK_INITIATE=false)   monitors but does not initiate the stack operation
(o) -n STACK_NAME               to override standard stack naming
(o) -r REGION                   is the AWS region identifier for the region in which the stack should be managed
(d) -s DEPLOYMENT_UNIT          same as -u
(m) -t TYPE                     is the stack type - "account", "product", "segment", "solution" or "application"
(m) -u DEPLOYMENT_UNIT          is the deployment unit used to determine the stack template
(o) -w STACK_WAIT               is the interval between checking the progress of the stack operation
(o) -y (DRYRUN=--dryrun)        for a dryrun - show what will happen without actually updating the strack

(m) mandatory, (o) optional, (d) deprecated

DEFAULTS:

STACK_INITIATE = ${STACK_INITIATE_DEFAULT}
STACK_MONITOR = ${STACK_MONITOR_DEFAULT}
STACK_OPERATION = ${STACK_OPERATION_DEFAULT}
STACK_WAIT = ${STACK_WAIT_DEFAULT} seconds

NOTES:
1. You must be in the correct directory corresponding to the requested stack type
2. REGION is only relevant for the "product" type, where multiple product stacks are necessary
   if the product uses resources in multiple regions
3. "segment" is now used in preference to "container" to avoid confusion with docker
4. If stack doesn't exist in AWS, the update operation will create the stack
5. Overriding the stack name is not recommended except where legacy naming has to be maintained
6. A dryrun creates a change set, then displays it. It only applies when
   the STACK_OPERATION=update

EOF
    exit
}

# Parse options
while getopts ":dhimn:r:s:t:u:w:y" opt; do
    case $opt in
        d)
            STACK_OPERATION=delete
            ;;
        h)
            usage
            ;;
        i)
            STACK_MONITOR=false
            ;;
        m)
            STACK_INITIATE=false
            ;;
        n)
            STACK_NAME="${OPTARG}"
            ;;
        r)
            REGION="${OPTARG}"
            ;;
        s)
            DEPLOYMENT_UNIT="${OPTARG}"
            ;;
        t)
            TYPE="${OPTARG}"
            ;;
        u)
            DEPLOYMENT_UNIT="${OPTARG}"
            ;;
        w)
            STACK_WAIT="${OPTARG}"
            ;;
        y)
            DRYRUN="--dryrun"
            ;;
        \?)
            echo -e "\nInvalid option: -${OPTARG}" >&2
            exit
            ;;
        :)
            echo -e "\nOption -${OPTARG} requires an argument" >&2
            exit
            ;;
    esac
done

# Apply defaults
STACK_OPERATION=${STACK_OPERATION:-${STACK_OPERATION_DEFAULT}}
STACK_WAIT=${STACK_WAIT:-${STACK_WAIT_DEFAULT}}
STACK_INITIATE=${STACK_INITIATE:-${STACK_INITIATE_DEFAULT}}
STACK_MONITOR=${STACK_MONITOR:-${STACK_MONITOR_DEFAULT}}


# Set up the context
. ${GENERATION_DIR}/setStackContext.sh

pushd ${CF_DIR} > /dev/null 2>&1

if [[ ! -f "$TEMPLATE" ]]; then
    echo -e "\n\"${TEMPLATE}\" not found. Are we in the correct place in the directory tree?" >&2
    exit
fi

# Assume all good
RESULT=0

if [[ "${STACK_INITIATE}" = "true" ]]; then
    case ${STACK_OPERATION} in
        delete)
            if [[ -n "${DRYRUN}" ]]; then
                echo -e "\nDryrun not applicable when deleting a stack" >&2
                exit
            fi

            aws --region ${REGION} cloudformation delete-stack --stack-name $STACK_NAME 2>/dev/null

            # For delete, we don't check result as stack may not exist

            # Delete any associated S3 files
            if [[ "${TYPE}" == "application" ]]; then
                deleteCMDBFilesFromOperationsBucket "appsettings"
                deleteCMDBFilesFromOperationsBucket "credentials"
            fi
            ;;

        update)
            # Compress the template to avoid aws cli size limitations
            jq -c '.' < ${TEMPLATE} > stripped_${TEMPLATE}
        
            # Check if stack needs to be created
            aws --region ${REGION} cloudformation describe-stacks --stack-name $STACK_NAME > $STACK 2>/dev/null
            RESULT=$?
            if [[ "$RESULT" -ne 0 ]]; then
                STACK_OPERATION="create"
            fi

            if [[ (-n "${DRYRUN}") && ("${STACK_OPERATION}" == "create") ]]; then
                echo -e "\nDryrun not applicable when creating a stack" >&2
                exit
            fi

            # Initiate the required operation
            if [[ -n "${DRYRUN}" ]]; then

                # Force monitoring to wait for change set to be complete
                STACK_OPERATION="create"
                STACK_MONITOR="true"

                # Change set naming
                CHANGE_SET_NAME="cs$(date +'%s')"
                STACK="temp_${CHANGE_SET_NAME}_${STACK}"
                aws --region ${REGION} cloudformation create-change-set --stack-name "${STACK_NAME}" --change-set-name "${CHANGE_SET_NAME}" --template-body file://stripped_${TEMPLATE} --capabilities CAPABILITY_IAM
            else
                aws --region ${REGION} cloudformation ${STACK_OPERATION,,}-stack --stack-name "${STACK_NAME}" --template-body file://stripped_${TEMPLATE} --capabilities CAPABILITY_IAM
            fi

            # Check result of operation
            RESULT=$?
            if [[ "$RESULT" -ne 0 ]]; then exit; fi
            
            # Update any S3 based files
            if [[ "${TYPE}" == "application" ]]; then
                syncCMDBFilesToOperationsBucket ${APPSETTINGS_DIR} "appsettings" ${DRYRUN}
                syncCMDBFilesToOperationsBucket ${CREDENTIALS_DIR} "credentials" ${DRYRUN}
            fi
            ;;

        *)
            echo -e "\n\"${STACK_OPERATION}\" is not one of the known stack operations." >&2
            exit
            ;;
    esac
fi

if [[ "${STACK_MONITOR}" = "true" ]]; then
    while true; do

        if [[ -n "${DRYRUN}" ]]; then
            STATUS_ATTRIBUTE="Status"
            aws --region ${REGION} cloudformation describe-change-set --stack-name "${STACK_NAME}" --change-set-name "${CHANGE_SET_NAME}" > "${STACK}" 2>/dev/null
            RESULT=$?
        else
            STATUS_ATTRIBUTE="StackStatus"
            aws --region ${REGION} cloudformation describe-stacks --stack-name "${STACK_NAME}" > "${STACK}" 2>/dev/null
            RESULT=$?
        fi

        if [[ ("${STACK_OPERATION}" == "delete") && ("${RESULT}" -eq 255) ]]; then
            # Assume stack doesn't exist
            RESULT=0
            break
        fi

        grep "${STATUS_ATTRIBUTE}" "${STACK}" > STATUS.txt
        cat STATUS.txt
        grep "${STACK_OPERATION^^}_COMPLETE" STATUS.txt >/dev/null 2>&1
        RESULT=$?
        if [[ "${RESULT}" -eq 0 ]]; then break;fi
        grep "${STACK_OPERATION^^}_IN_PROGRESS" STATUS.txt  >/dev/null 2>&1
        RESULT=$?
        if [[ "${RESULT}" -ne 0 ]]; then break;fi
        sleep ${STACK_WAIT}
    done
fi

if [[ "${STACK_OPERATION}" == "delete" ]]; then
    if [[ ("${RESULT}" -eq 0) || !( -s "${STACK}" ) ]]; then
        rm -f "${STACK}"
    fi
fi
if [[ -n "${DRYRUN}" ]]; then
    cat "${STACK}"
fi

