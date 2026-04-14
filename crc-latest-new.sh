#!/bin/bash

#set -x

function verify_bundle_exist() {
    check_address=$1/$2
    echo "verify existing of $check_address"
    valid_code=$(curl -s -fI -o /dev/null -w "%{http_code}" $check_address)
    echo $valid_code
    if [ $valid_code != 200 ]; then
        echo "The url of $check_address not accessible, please check again"
        exit 1
    fi
}

function create_yaml_file(){
    file="test/$1-$2.yaml"
    echo "creating yaml file for $file"

    B_preset=""
    if [[ $2 == "microshift" ]]; then
        B_preset="_microshift"
    fi

    if [[ $1 == 'linux-arm' ]]; then
        cp -r template/crc-latest-arm64-temp-new.yaml $file
        sed -i'' -e "s#<Bundle-path>#${bundlePathArm}#g"  $file

        bundleName=crc${B_preset}_libvirt_${bundle}_arm64.crcbundle
        sed -i'' -e "s#<Bundle-name>#${bundleName}#g"  $file

    else
        cp -r template/crc-latest-template-new.yaml $file
        sed -i'' -e "s#<Bundle-path>#${bundlePath}#g"  $file

        arch="amd64"
        status=$pendingStatus
        if [[ $1 == "windows" ]]; then
            vm="hyperv"
            builder="secret-windows-1-blr"
            tester="secret-windows-1-brno"
        elif [[ $1 == mac* ]]; then
            vm="vfkit"
            builder="secret-mac-1-brno"
            if [[ $1 == *-arm ]]; then
                arch="arm64"
                tester="secret-mac-7-brno"
            else
                tester="secret-mac-2-brno"
            fi
        elif [[ $1 == linux-amd ]]; then
            vm="libvirt"
            builder="''"
            tester="secret-rhel-1-brno"
        fi

        bundleName=crc${B_preset}_${vm}_${bundle}_${arch}.crcbundle

        sed -i'' -e "s#<tester>#$tester#g"  $file
        sed -i'' -e "s#<builder>#$builder#g"  $file
        sed -i'' -e "s#<status>#$status#g"  $file
        sed -i'' -e "s#<Bundle-name>#${bundleName}#g"  $file
    fi

    sed -i'' -e "s#<B-VERSION>#${bundle}#g"  $file
    sed -i'' -e "s#<DEBUG>#${debug}#g"  $file
    sed -i'' -e "s#<CRC-PR>#'$crcPR'#g"  $file
    sed -i'' -e "s#<RUN-e2e>#${runE2E}#g"  $file
    sed -i'' -e "s#<E2Etag>#${e2eTag}#g"  $file
    sed -i'' -e "s#<RUN-integration>#${runIntegration}#g"  $file
    sed -i'' -e "s#<integration-tag>#${integrationTag}#g"  $file
    sed -i'' -e "s#<S3>#${s3path}#g"  $file
    sed -i'' -e "s#<platform>#$1#g"  $file
    sed -i'' -e "s#<PURPOSE>#$purpose1#g"  $file
    sed -i'' -e "s#<preset>#$preset#g"  $file

    if [[ $purpose == 'snc-pr-test' ]] || [[ $purpose == 'interop-test' ]] && [[ $1 == *-arm ]]; then
        sed -i'' -e "s#<SHA-FILE>#${bundleShaArm}#g"  $file
    else
        sed -i'' -e "s#<SHA-FILE>#${bundleSha}#g"  $file
    fi

    if [[ $1 == linux-amd ]]; then
        sed -i'' -e '7d' $file
    fi
}

function help() {
  cat << EOF
Usage: $0"
	-p,--purpose
		bundle-test
		interop-test
		nightly-run
		crc-pr-test
		snc-pr-test
		other			Type of test, default nightly-run"
	--platform			Which OS to run default: windows,mac-amd,mac-arm,linux-amd,linux-arm"
	-b,--bundle <bundle>		Change bundle to run with, default: set by current crc version"
	--preset openshift/microshift	Container type, default openshift"
	--e2e				Whether run e2e test, default true"
	--e2etag			Tags for e2e test, default ~@minimal && ~@story_microshift && ~@release"
	--integration			Whether run integration test, default true"
	--integrationtag		Tags for integration test, default ! microshift-preset"
	-r,--pr <pr>			Run against PR instead of tip"
	--trigger true|false 		Create pipeline run with yaml files, default false"
	-d true|false			Enable debug
EOF
}


if [[ "$#" -eq 0 ]]; then
  echo "using -h/--help to check parameters"
  exit 1
fi

preset="openshift"
runE2E='true'
runIntegration='true'
platforms="windows,mac-amd,mac-arm,linux-amd,linux-arm"
purpose="nightly-run"
debug='false'
trigger='false'
pendingStatus="PipelineRunPending"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
        help
        exit ;;
    -p|--purpose)
        purpose=$2;
        shift 2 ;;
    -r|--pr)
        pr=$2;
        shift 2 ;;
    -b|--bundle)
        bundle=$2;
        shift 2 ;;
    --preset)
        preset=$2;
        shift 2 ;;
    --platform)
        platforms=$2;
        shift 2 ;;
    --e2e)
        runE2E=$2;
        shift 2 ;;
    --e2etag)
        e2eTag=$2;
        shift 2 ;;
    --integration)
        runIntegration=$2;
        shift 2 ;;
    --integrationtag)
        integrationTag=$2;
        shift 2 ;;
    -d|--debug)
        debug=$2;
        shift 2 ;;
    --trigger)
        trigger=$2;
        shift 2 ;;
    *)
        cat <&2 <<EOF

Error, unknown arguments $@
EOF
         help
         exit 1 ;;
  esac
done

echo "Purpose: $purpose"
echo "Preset: $preset"
if [[ $bundle == '' ]]; then
  echo "please input the bundle version"
  exit 1
fi
echo "Bundle: $bundle"


today=`date +"%Y%m%d"`

# deal with bundle path and s3 path
bundleSha="sha256sum.txt"
crcPR=''
s3path="nightly/crc/$today"
bundlePath="https://cdk-builds.usersys.redhat.com/builds/crc/bundles/$preset"
bundlePathArm="https://crcqe-asia.s3.ap-south-1.amazonaws.com/bundles/$preset"
bundleShaArm=""
purpose1=$purpose

if [[ $purpose == 'snc-pr-test' ]]; then
  bundlePath="https://crc-bundle.s3.us-east-1.amazonaws.com/snc-pr/${pr}"
  bundlePathArm=$bundlePath
  bundleSha="bundles.x86_64.sha256"
  bundleShaArm="bundles.arm64.sha256"
  verify_bundle_exist $bundlePath/$bundle $bundleSha
  verify_bundle_exist $bundlePath/$bundle $bundleShaArm
  s3path="nightly/crc/snc-pr/${pr}"
  purpose1=${purpose}-${pr}
elif [[ $purpose == 'interop-test' ]]; then
  bundlePath="https://crc-bundle.s3.us-east-1.amazonaws.com"
  bundlePathArm=$bundlePath
  bundleSha="bundles.x86_64.sha256"
  bundleShaArm="bundles.arm64.sha256"
  verify_bundle_exist $bundlePath/$bundle $bundleSha
  verify_bundle_exist $bundlePath/$bundle $bundleShaArm
  s3path="nightly/ocp"
else
  verify_bundle_exist $bundlePath/$bundle $bundleSha
  verify_bundle_exist $bundlePathArm/$bundle $bundleSha

  if [[ $purpose == 'crc-pr-test' ]]; then
    crcPR=$pr
    s3path="nightly/crc/crc-pr/${pr}"
    purpose1=${purpose}-${pr}
  fi
fi


# deal with the default e2e and integration tags
e2eTagOcp="~@minimal \&\& ~@story_microshift"
integrationTagOcp="! microshift-preset"
e2eTagMicroshift="@story_microshift"
integrationTagMicroshift="microshift-preset"
if [[ $preset == "microshift" ]]; then
  if [[ $e2eTag == ''  ]]; then
    e2eTag=$e2eTagMicroshift
  fi
  if [[ $integrationTag == '' ]]; then
    integrationTag=$integrationTagMicroshift
  fi
else
  if [[ $e2eTag == ''  ]]; then
    e2eTag=$e2eTagOcp
  fi
  if [[ $integrationTag == '' ]]; then
    integrationTag=$integrationTagOcp
  fi
fi



# ENV:
# 1. test purpose
# 2. bundle version
# 3. crc-pr
# 4. snc-pr
# 5. bundle-shasumfile
# 6. run-e2e
# 7. e2e-tag
# 8. run-integration
# 9. integration-tag
# 10. debug

if [ -d "test" ];then
 rm -r test
fi
mkdir test
# Create pipeline run yaml file
IFS=',' read -ra allplatform <<< "$platforms"
for p in "${allplatform[@]}"; do
  create_yaml_file $p $preset
done

if [[ $trigger == 'true' ]]; then
  oc project | grep "devtoolsqe--pipeline" || (echo set project to devtoolsqe-pipeline && exit 1)
  oc create -f test
else
  echo "pipeline run yaml files created in folder test"
fi

