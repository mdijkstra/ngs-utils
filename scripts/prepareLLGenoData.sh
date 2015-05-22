#!/bin/bash

set -u
set -e

#
# Defaults
#
RunId=""
Data=""
PseudoDir="/gcc/groups/lifelines/home/rsnieders/GenoPseudo"
SampleSheet="/gcc/groups/lifelines/prm02/samplesheets/"
makedir="mkdir -p -m 770"
SNPSubset="all"

module load LL_genodata/20150311
#
# Load tools into environment.
#
module load jdk

#
# Check if we are on the right UI to generate and submit LifeLines jobs.
#
if [[ "$(hostname)" != "scheduler02" ]]; then 
	echo "FATAL: You should be on scheduler02 to run this script."
	exit 1
fi

function usage () {
	echo "
	Required:
        -r|--runid		Put here the runnumber
                        	e.g. OV10_0051

        -d|--data		Give the type of Data (Unimputed,1000G,GONL or HapMap2)

	Optional:
	-s|--snpsubset		You can choose if you only want to select a subset of snps that needs analyzed. Complete path to the file

	-p|--pseudodir		Absolute path of the directory of the pseudofile
				Pseudo file name must be: \${runid}.txt
				Pseudo files are usually located in /gcc/groups/lifelines/home/\${datamanager}/GenoPseudo/
	"
}

PARSED_OPTIONS=$(getopt -n "$0"  -o r:d:p:s: --long "runid:,data:,pseudodir:,snpsubset:"  -- "$@")

#
# Bad arguments, something has gone wrong with the getopt command.
#
if [ $? -ne 0 ]; then
	usage
	echo "FATAL: Wrong arguments."
	exit 1
fi

eval set -- "$PARSED_OPTIONS"

#
# Now goes through all the options with a case and using shift to analyse 1 argument at a time.
# $1 identifies the first argument, and when we use shift we discard the first argument, so $2 becomes $1 and goes again through the case.
#
while true; do
  case "$1" in
	-p|--pseudodir)
        	case "$2" in
		"") shift 2 ;;
                *) PseudoDir=$2 ; shift 2 ;;
            esac ;;
   	-r|--runid)
		case "$2" in
                *) RunId=$2 ; shift 2 ;;
            esac ;;
	-s|--snpsubset)
                case "$2" in
                *) SNPSubset=$2 ; shift 2 ;;
            esac ;;
   	-d|--data)
		case "$2" in 
		*) Data=$2 ; shift 2 ;;
            esac ;; 
    	--) shift ; break ;;
	*) echo "Internal error!" ; exit 1 ;;
  esac
done

#
# Check required options were provided. 
#
if [[ -z "${RunId-}" || -z "${Data-}" ]]; then
	usage
        echo "FATAL: missing required parameter."
	exit 1
fi

GeneratedScript="/gcc/groups/lifelines/tmp03/lifelines/generatedscripts/${RunId}/"

if [[ "${Data}" == "Unimputed" || "${Data}" == "HapMap2" || "${Data}" == "GONL" || "${Data}" == "1000G" ]]; then 
	echo "Requested data type is: ${Data}."
else
	usage
	echo "FATAL: Unkown data type. Please choose one of 'Unimputed', 'HapMap2', 'GONL' or '1000G'"
	exit 1
fi 

echo "INFO: Using pseudodir ${PseudoDir}."
echo "INFO: Using runid     ${RunId}."
echo "INFO: Using data      ${Data}."
echo "INFO: Using snpsubset ${SNPSubset}."

#copy pseudofile to tmp
cp /gcc/groups/lifelines/prm02/pseudoFiles/${RunId}.txt /gcc/groups/lifelines/tmp03/lifelines/pseudoFiles/${RunId}.txt

#
# Go to samplesheets on permanent storage.
#
cd "${SampleSheet}"

#
# Copy an already existing old run mapping file.
#
if [ ${SNPSubset} != "all" ];
then
	if [ ! -f ${SNPSubset} ];
	then
		echo "The file does not exist!"
		return -1
	else
		cp "${SampleSheet}/example_${Data}_subset.csv" "${SampleSheet}/${RunId}_${Data}.csv"
		perl -pi -e "s|,subset|,${SNPSubset}|g" ${SampleSheet}/${RunId}_${Data}.csv
	fi
else
	cp "${SampleSheet}/example_${Data}.csv" "${SampleSheet}/${RunId}_${Data}.csv"
fi 

#
# Rename the old run number in the file.
#
perl -pi -e "s|example|${RunId}|g" "${RunId}_${Data}.csv"

#
# Make directory in generatedscripts.
#
if [ ! -e "${GeneratedScript}" ]; then
	${makedir} ${GeneratedScript}
	echo "created folder: ${GeneratedScript}"
	cd ${GeneratedScript}
	${makedir} ${Data}
elif [[ -d "${GeneratedScript}" && -r "${GeneratedScript}" && -w "${GeneratedScript}" && -x "${GeneratedScript}" ]]; then
	echo "INFO: Directory already exists, and we have rwx permissions."
	cd "${GeneratedScript}"
	if [ ! -d "${Data}" ]; then
		${makedir} "${Data}"
	fi
else
	echo "FATAL: The ${GeneratedScript} folder already exists, but you don't have read, write or execute rights."
	exit 1
fi

WORKFLOW=""

if [ ${Data} == "Unimputed" ]; then
	WORKFLOW="workflowUnimputedData.csv"
else
	WORKFLOW="workflow.csv"
fi

Jobs="/gcc/groups/lifelines/tmp03/lifelines/projects/lifelines_${RunId}/${Data}/jobs/"


#
# Generate jobs.
#
sh ${LL_GENO_HOME}/molgenis_compute.sh -b pbs -p ${SampleSheet}/${RunId}_${Data}.csv \
-p ${LL_GENO_HOME}/pipelines/LifeLines_update_genotype_data/parameters.csv \
-w ${LL_GENO_HOME}/pipelines/LifeLines_update_genotype_data/${WORKFLOW} \
-rundir ${Jobs} \
-weave

#
# Go to the jobs folder.
#
cd ${Jobs}

#
# Now change the queue from ‘PBS’ to ‘devel’ since you are on scheduler02.
#
perl -pi -e 's/#PBS -q gaf/#PBS -q devel/g' *.sh

#
# Signal success.
#
echo "INFO: Finished generating jobs, you may now run ${Jobs}/submit.sh..."
exit 0
