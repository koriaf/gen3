#!/bin/bash

if [[ -n "${GENERATION_DEBUG}" ]]; then set ${GENERATION_DEBUG}; fi
trap '. ${GENERATION_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

# Defaults
CONFIGURATION_REFERENCE_DEFAULT="unassigned"
REQUEST_REFERENCE_DEFAULT="unassigned"

function usage() {
    cat <<EOF

Create a CloudFormation (CF) template

Usage: $(basename $0) -t TYPE -u DEPLOYMENT_UNIT -b BUILD_DEPLOYMENT_UNIT -c CONFIGURATION_REFERENCE -q REQUEST_REFERENCE -r REGION

where

(m) -b BUILD_DEPLOYMENT_UNIT   is the deployment unit defining the build reference
(m) -c CONFIGURATION_REFERENCE is the identifier of the configuration used to generate this template
    -h                         shows this text
(m) -q REQUEST_REFERENCE       is an opaque value to link this template to a triggering request management system
(o) -r REGION                  is the AWS region identifier
(d) -s DEPLOYMENT_UNIT         same as -u
(m) -t TYPE                    is the template type - "account", "product", "segment", "solution" or "application"
(m) -u DEPLOYMENT_UNIT         is the deployment unit to be included in the template

(m) mandatory, (o) optional, (d) deprecated

DEFAULTS:

CONFIGURATION_REFERENCE = "${CONFIGURATION_REFERENCE_DEFAULT}"
REQUEST_REFERENCE       = "${REQUEST_REFERENCE_DEFAULT}"

NOTES:

1. You must be in the directory specific to the type
2. REGION is only relevant for the "product" type
3. DEPLOYMENT_UNIT may be one of "s3" or "cert" for the "account" type
4. DEPLOYMENT_UNIT may be one of "cmk", "cert", "sns" or "shared" for the "product" type
5. DEPLOYMENT_UNIT may be one of "eip", "s3", "cmk", "cert", "vpc" or "dns" for the "segment" type
6. Stack for DEPLOYMENT_UNIT of "eip" or "s3" must be created before stack for "vpc" for the "segment" type
7. Stack for DEPLOYMENT_UNIT of "vpc" must be created before stack for "dns" for the "segment" type
8. To support legacy configurations, the DEPLOYMENT_UNIT combinations "eipvpc" and "eips3vpc" 
   are also supported but for new products, individual templates for each deployment unit 
   should be created

EOF
    exit
}

# Parse options
while getopts ":b:c:hq:r:s:t:u:" opt; do
    case $opt in
        b)
            BUILD_DEPLOYMENT_UNIT="${OPTARG}"
            ;;
        c)
            CONFIGURATION_REFERENCE="${OPTARG}"
            ;;
        h)
            usage
            ;;
        q)
            REQUEST_REFERENCE="${OPTARG}"
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

# Defaults
CONFIGURATION_REFERENCE="${CONFIGURATION_REFERENCE:-${CONFIGURATION_REFERENCE_DEFAULT}}"
REQUEST_REFERENCE="${REQUEST_REFERENCE:-${REQUEST_REFERENCE_DEFAULT}}"

# Ensure mandatory arguments have been provided
if [[ (-z "${TYPE}") ||
        (-z "${DEPLOYMENT_UNIT}") ||
        (-z "${REQUEST_REFERENCE}") ||
        (-z "${CONFIGURATION_REFERENCE}")]]; then
    echo -e "\nInsufficient arguments" >&2
    exit
fi
if [[ ("${TYPE}" == "account") && 
      (!("${DEPLOYMENT_UNIT}" =~ s3|cert)) ]]; then
    echo -e "\nUnknown deployment unit ${DEPLOYMENT_UNIT} for the account type" >&2
    exit
fi
if [[ ("${TYPE}" == "product") && 
      (!("${DEPLOYMENT_UNIT}" =~ s3|sns|cmk|cert)) ]]; then
    echo -e "\nUnknown deployment unit ${DEPLOYMENT_UNIT} for the product type" >&2
    exit
fi
if [[ ("${TYPE}" == "segment") && 
      (!("${DEPLOYMENT_UNIT}" =~ eip|s3|cmk|cert|vpc|dns|eipvpc|eips3vpc)) ]]; then
    echo -e "\nUnknown deployment unit ${DEPLOYMENT_UNIT} for the segment type" >&2
    exit
fi

# Set up the context
. ${GENERATION_DIR}/setContext.sh

# Ensure we are in the right place
case $TYPE in
    account|product)
        if [[ ! ("${TYPE}" =~ ${LOCATION}) ]]; then
            echo "Current directory doesn't match requested type \"${TYPE}\". Are we in the right place?" >&2
            exit
        fi
        ;;
    solution|segment|application)
        if [[ ! ("segment" =~ ${LOCATION}) ]]; then
            echo "Current directory doesn't match requested type \"${TYPE}\". Are we in the right place?" >&2
            exit
        fi
        ;;
esac

# Set up the type specific template information
TEMPLATE_DIR="${GENERATION_DIR}/templates"
TEMPLATE="create${TYPE^}Template.ftl"
COMPOSITE_VAR="COMPOSITE_${TYPE^^}"

# Determine the template name
TYPE_PREFIX="$TYPE-"
DEPLOYMENT_UNIT_PREFIX="${DEPLOYMENT_UNIT}-"
REGION_PREFIX="${REGION}-"
case $TYPE in
    account)
        CF_DIR="${INFRASTRUCTURE_DIR}/${ACCOUNT}/aws/cf"
        REGION_PREFIX="${ACCOUNT_REGION}-"

        # LEGACY: Support stacks created before deployment units added to account
        if [[ "${DEPLOYMENT_UNIT}" =~ s3 ]]; then
            if [[ -f "${CF_DIR}/${TYPE_PREFIX}${REGION_PREFIX}template.json" ]]; then
                DEPLOYMENT_UNIT_PREFIX=""
            fi
        fi
        ;;

    product)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PRODUCT}/aws/cf"

        # LEGACY: Support stacks created before deployment units added to product
        if [[ "${DEPLOYMENT_UNIT}" =~ cmk ]]; then
            if [[ -f "${CF_DIR}/${TYPE_PREFIX}${REGION_PREFIX}template.json" ]]; then
                DEPLOYMENT_UNIT_PREFIX=""
            fi
        fi
        ;;

    solution)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PRODUCT}/aws/${SEGMENT}/cf"
        TYPE_PREFIX="soln-"
        if [[ -f "${CF_DIR}/solution-${REGION}-template.json" ]]; then
            TYPE_PREFIX="solution-"
            DEPLOYMENT_UNIT_PREFIX=""
        fi
        ;;

    segment)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PRODUCT}/aws/${SEGMENT}/cf"
        TYPE_PREFIX="seg-"

        # LEGACY: Support old formats for existing stacks so they can be updated 
        if [[ !("${DEPLOYMENT_UNIT}" =~ cmk|cert|dns ) ]]; then
            if [[ -f "${CF_DIR}/cont-${DEPLOYMENT_UNIT_PREFIX}${REGION_PREFIX}template.json" ]]; then
                TYPE_PREFIX="cont-"
            fi
            if [[ -f "${CF_DIR}/container-${REGION}-template.json" ]]; then
                TYPE_PREFIX="container-"
                DEPLOYMENT_UNIT_PREFIX=""
            fi
            if [[ -f "${CF_DIR}/${SEGMENT}-container-template.json" ]]; then
                TYPE_PREFIX="${SEGMENT}-container-"
                DEPLOYMENT_UNIT_PREFIX=""
                REGION_PREFIX=""
            fi
        fi
        # "cmk" now used instead of "key"
        if [[ "${DEPLOYMENT_UNIT}" == "cmk" ]]; then
            if [[ -f "${CF_DIR}/${TYPE_PREFIX}key-${REGION_PREFIX}template.json" ]]; then
                DEPLOYMENT_UNIT_PREFIX="key-"
            fi
        fi
        ;;

    application)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PRODUCT}/aws/${SEGMENT}/cf"
        TYPE_PREFIX="app-"

#        TODO: reinstate this check when the logic to list the application
#               deployment units is fixed. It broke for lambda when defaulting of
#               the set of functions (to potentially higher levels that the 
#               deployment unit) was added
#        if [[ "${IS_APPLICATION_DEPLOYMENT_UNIT}" != "true" ]]; then
#            echo -e "\n\"${DEPLOYMENT_UNIT}\" is not defined as an application deployment unit in the blueprint" >&2
#            exit
#        fi
        ;;

    *)
        echo -e "\n\"${TYPE}\" is not one of the known stack types (account, product, segment, solution, application). Nothing to do." >&2
        exit
        ;;
esac

# Generate the template filename
OUTPUT="${CF_DIR}/${TYPE_PREFIX}${DEPLOYMENT_UNIT_PREFIX}${REGION_PREFIX}template.json"
TEMP_OUTPUT="${CF_DIR}/temp_${TYPE_PREFIX}${DEPLOYMENT_UNIT_PREFIX}${REGION_PREFIX}template.json"

# Ensure the aws tree for the templates exists
if [[ ! -d ${CF_DIR} ]]; then mkdir -p ${CF_DIR}; fi

ARGS=()
if [[ -n "${DEPLOYMENT_UNIT}" ]]; then ARGS+=("-v" "deploymentUnit=${DEPLOYMENT_UNIT}"); fi
if [[ -n "${BUILD_DEPLOYMENT_UNIT}" ]]; then ARGS+=("-v" "buildDeploymentUnit=${BUILD_DEPLOYMENT_UNIT}"); fi
if [[ -n "${BUILD_REFERENCE}" ]]; then ARGS+=("-v" "buildReference=${BUILD_REFERENCE}"); fi

# Removal of drive letter (/?/) is specifically for MINGW
# It shouldn't affect other platforms as it won't be matched
if [[ -n "${!COMPOSITE_VAR}"     ]]; then ARGS+=("-r" "${TYPE}List=${!COMPOSITE_VAR#/?/}"); fi
if [[ "${TYPE}" == "application" ]]; then ARGS+=("-r" "containerList=${COMPOSITE_CONTAINER#/?/}"); fi
ARGS+=("-r" "idList=${COMPOSITE_ID#/?/}")
ARGS+=("-r" "nameList=${COMPOSITE_NAME#/?/}")
ARGS+=("-r" "policyList=${COMPOSITE_POLICY#/?/}")
ARGS+=("-v" "region=${REGION}")
ARGS+=("-v" "productRegion=${PRODUCT_REGION}")
ARGS+=("-v" "accountRegion=${ACCOUNT_REGION}")
ARGS+=("-v" "blueprint=${COMPOSITE_BLUEPRINT}")
ARGS+=("-v" "credentials=${COMPOSITE_CREDENTIALS}")
ARGS+=("-v" "appsettings=${COMPOSITE_APPSETTINGS}")
ARGS+=("-v" "stackOutputs=${COMPOSITE_STACK_OUTPUTS}")
ARGS+=("-v" "requestReference=${REQUEST_REFERENCE}")
ARGS+=("-v" "configurationReference=${CONFIGURATION_REFERENCE}")

${GENERATION_DIR}/freemarker.sh -t ${TEMPLATE} -d ${TEMPLATE_DIR} -o "${TEMP_OUTPUT}" "${ARGS[@]}"
RESULT=$?
if [[ "${RESULT}" -eq 0 ]]; then
    # Tidy up the result
    jq --indent 4 '.' < "${TEMP_OUTPUT}" > "${OUTPUT}"
fi
