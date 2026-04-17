#!/bin/bash

if [ $# == 0 ] ; then
echo "USAGE: \$1 The bundle Version"
exit 1;
fi

function verify_bundle_exist() {
    check_address=${1}/sha256sum.txt
    #echo "verify existing of $check_address"
    valid_code=$(curl -s -fI -o /dev/null -w "%{http_code}" $check_address)
    #echo $valid_code
    if [ $valid_code != 200 ]; then
        echo "The url of $check_address not accessible"
        return 1
    fi
    return 0
}


if [ -d "test" ];then
 rm -r test
fi
mkdir test

bundle_version=$1

presets=(openshift microshift)

for i in ${presets[@]}; do
    echo "creating yaml file for $i $bundle_version upload "
    file="test/upload-bundle-$i.yaml"
    cp -r template/upload-bundle-template.yaml $file

    bundleUrl="https://cdk-builds.usersys.redhat.com/builds/crc/bundles/$i/${bundle_version}"
    if [ $i == "openshift" ]; then
        bundlename="crc_libvirt_${bundle_version}_arm64.crcbundle"
    else
        bundlename="crc_microshift_libvirt_${bundle_version}_arm64.crcbundle"
    fi
    echo "$bundleUrl/$bundlename"
    if ! verify_bundle_exist "$bundleUrl"; then
        echo "The bundle $bundleUrl/$bundlename do not exist, so it will be removed"
        rm $file
        continue
    fi
    sed -i'' -e "s#<Bundle_url>#$bundleUrl#g"  $file
    sed -i'' -e "s#<Preset>#$i#g"  $file
    sed -i'' -e "s#<Bundle_version>#${bundle_version}#g"  $file
    sed -i'' -e "s#<Bundle_name>#${bundlename}#g"  $file
done

oc project | grep "devtoolsqe--pipeline"
oc create -f test
