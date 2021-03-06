[#-- EC2 --]
[#if componentType == "ec2"]
    [#assign ec2 = component.EC2]
    [#assign fixedIP = ec2.FixedIP?? && ec2.FixedIP]

    [#assign ec2FullName = componentFullName ]
    [#assign ec2SecurityGroupId = formatEC2SecurityGroupId(tier, component)]
    [#assign ec2RoleId = formatEC2RoleId(tier, component)]
    [#assign ec2InstanceProfileId = formatEC2InstanceProfileId(tier, component)]
    [#assign ec2ELBId = formatELBId("elb", component)]
    [@createComponentSecurityGroup solutionListMode tier component /]
    
    [#if resourceCount > 0],[/#if]
    [#switch solutionListMode]
        [#case "definition"]
            [#list ec2.Ports as port]
                "${formatEC2SecurityGroupIngressId(
                    tier,
                    component,
                    ports[port])}" : {
                    "Type" : "AWS::EC2::SecurityGroupIngress",
                    "Properties" : {
                        "GroupId": {"Ref" : "${ec2SecurityGroupId}"},
                        "IpProtocol": "${ports[port].IPProtocol}",
                        "FromPort": "${ports[port].Port?c}",
                        "ToPort": "${ports[port].Port?c}",
                        "CidrIp": "0.0.0.0/0"
                    }
                },
            [/#list]
            "${ec2RoleId}": {
                "Type" : "AWS::IAM::Role",
                "Properties" : {
                    "AssumeRolePolicyDocument" : {
                        "Version": "2012-10-17",
                        "Statement": [
                            {
                                "Effect": "Allow",
                                "Principal": { "Service": [ "ec2.amazonaws.com" ] },
                                "Action": [ "sts:AssumeRole" ]
                            }
                        ]
                    },
                    "Path": "/",
                    "Policies": [
                        {
                            "PolicyName": "${formatComponentShortName(
                                                tier,
                                                component,
                                                "basic")}",
                            "PolicyDocument" : {
                                "Version": "2012-10-17",
                                "Statement": [
                                    {
                                        "Resource": [
                                            "arn:aws:s3:::${codeBucket}",
                                            "arn:aws:s3:::${operationsBucket}"
                                        ],
                                        "Action": [
                                            "s3:List*"
                                        ],
                                        "Effect": "Allow"
                                    },
                                    {
                                        "Resource": [
                                            "arn:aws:s3:::${codeBucket}/*"
                                        ],
                                        "Action": [
                                            "s3:GetObject"
                                        ],
                                        "Effect": "Allow"
                                    },
                                    {
                                        "Resource": [
                                            "arn:aws:s3:::${operationsBucket}/DOCKERLogs/*",
                                            "arn:aws:s3:::${operationsBucket}/Backups/*"
                                        ],
                                        "Action": [
                                            "s3:PutObject"
                                        ],
                                        "Effect": "Allow"
                                    }
                                ]
                            }
                        }
                    ]
                }
            },

            "${ec2InstanceProfileId}" : {
                "Type" : "AWS::IAM::InstanceProfile",
                "Properties" : {
                    "Path" : "/",
                    "Roles" : [
                        { "Ref" : "${ec2RoleId}" }
                    ]
                }
            }

            [#list zones as zone]
                [#if multiAZ || (zones[0].Id = zone.Id)]
                    [#assign ec2InstanceId =
                                formatEC2InstanceId(
                                    tier,
                                    component,
                                    zone)]
                    [#assign ec2ENIId = 
                                formatEC2ENIId(
                                    tier,
                                    component,
                                    zone,
                                    "eth0")]
                    [#assign ec2EIPId = formatComponentEIPId(
                                            tier,
                                            component,
                                            zone)]
                    [#-- Support backwards compatability with existing installs --] 
                    [#if !(getKey(ec2EIPId)?has_content)]
                        [#assign ec2EIPId = formatComponentEIPId(
                                                tier,
                                                component,
                                                zone
                                                "eth0")]
                    [/#if]

                    [#assign ec2EIPAssociationId = 
                                formatComponentEIPAssociationId(
                                    tier,
                                    component,
                                    zone,
                                    "eth0")]

                    ,"${ec2InstanceId}": {
                        "Type": "AWS::EC2::Instance",
                        "Metadata": {
                            "AWS::CloudFormation::Init": {
                                "configSets" : {
                                    "ec2" : ["dirs", "bootstrap", "puppet"]
                                },
                                "dirs": {
                                    "commands": {
                                        "01Directories" : {
                                            "command" : "mkdir --parents --mode=0755 /etc/codeontap && mkdir --parents --mode=0755 /opt/codeontap/bootstrap && mkdir --parents --mode=0755 /var/log/codeontap",
                                            "ignoreErrors" : "false"
                                        }
                                    }
                                },
                                "bootstrap": {
                                    "packages" : {
                                        "yum" : {
                                            "aws-cli" : []
                                        }
                                    },
                                    "files" : {
                                        "/etc/codeontap/facts.sh" : {
                                            "content" : {
                                                "Fn::Join" : [
                                                    "",
                                                    [
                                                        "#!/bin/bash\n",
                                                        "echo \"cot:request=${requestReference}\"\n",
                                                        "echo \"cot:configuration=${configurationReference}\"\n",
                                                        "echo \"cot:accountRegion=${accountRegionId}\"\n",
                                                        "echo \"cot:tenant=${tenantId}\"\n",
                                                        "echo \"cot:account=${accountId}\"\n",
                                                        "echo \"cot:product=${productId}\"\n",
                                                        "echo \"cot:region=${regionId}\"\n",
                                                        "echo \"cot:segment=${segmentId}\"\n",
                                                        "echo \"cot:environment=${environmentId}\"\n",
                                                        "echo \"cot:tier=${tierId}\"\n",
                                                        "echo \"cot:component=${componentId}\"\n",
                                                        "echo \"cot:zone=${zone.Id}\"\n",
                                                        "echo \"cot:name=${ec2FullName}\"\n",
                                                        "echo \"cot:role=${component.Role}\"\n",
                                                        "echo \"cot:credentials=${credentialsBucket}\"\n",
                                                        "echo \"cot:code=${codeBucket}\"\n",
                                                        "echo \"cot:logs=${operationsBucket}\"\n",
                                                        "echo \"cot:backup=${dataBucket}\"\n"
                                                    ]
                                                ]
                                            },
                                            "mode" : "000755"
                                        },
                                        "/opt/codeontap/bootstrap/fetch.sh" : {
                                            "content" : {
                                                "Fn::Join" : [
                                                    "",
                                                    [
                                                        "#!/bin/bash -ex\n",
                                                        "exec > >(tee /var/log/codeontap/fetch.log|logger -t codeontap-fetch -s 2>/dev/console) 2>&1\n",
                                                        "REGION=$(/etc/codeontap/facts.sh | grep cot:accountRegion= | cut -d '=' -f 2)\n",
                                                        "CODE=$(/etc/codeontap/facts.sh | grep cot:code= | cut -d '=' -f 2)\n",
                                                        "aws --region ${r"${REGION}"} s3 sync s3://${r"${CODE}"}/bootstrap/centos/ /opt/codeontap/bootstrap && chmod 0755 /opt/codeontap/bootstrap/*.sh\n"
                                                    ]
                                                ]
                                            },
                                            "mode" : "000755"
                                        }
                                    },
                                    "commands": {
                                        "01Fetch" : {
                                            "command" : "/opt/codeontap/bootstrap/fetch.sh",
                                            "ignoreErrors" : "false"
                                        },
                                        "02Initialise" : {
                                            "command" : "/opt/codeontap/bootstrap/init.sh",
                                            "ignoreErrors" : "false"
                                        }
                                        [#if ec2.LoadBalanced]
                                            ,"03RegisterWithLB" : {
                                                "command" : "/opt/codeontap/bootstrap/register.sh",
                                                "env" : {
                                                    "LOAD_BALANCER" : { "Ref" : "${ec2ELBId}" }
                                                },
                                                "ignoreErrors" : "false"
                                            }
                                        [/#if]
                                    }
                                },
                                "puppet": {
                                    "commands": {
                                        "01SetupPuppet" : {
                                            "command" : "/opt/codeontap/bootstrap/puppet.sh",
                                            "ignoreErrors" : "false"
                                        }
                                    }
                                }
                            }
                        },
                        [#assign processorProfile = getProcessor(tier, component, "EC2")]
                        [#assign storageProfile = getStorage(tier, component, "EC2")]
                        "Properties": {
                            [@createBlockDevices storageProfile=storageProfile /]
                            "DisableApiTermination" : false,
                            "EbsOptimized" : false,
                            "IamInstanceProfile" : { "Ref" : "${ec2InstanceProfileId}" },
                            "ImageId": "${regionObject.AMIs.Centos.EC2}",
                            "InstanceInitiatedShutdownBehavior" : "stop",
                            "InstanceType": "${processorProfile.Processor}",
                            "KeyName": "${productName + sshPerSegment?string("-" + segmentName,"")}",
                            "Monitoring" : false,
                            "NetworkInterfaces" : [
                                {
                                    "DeviceIndex" : "0",
                                    "NetworkInterfaceId" : { "Ref" : "${ec2ENIId}" }
                                }
                            ],
                            "Tags" : [
                                { "Key" : "cot:request", "Value" : "${requestReference}" },
                                { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                                { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                                { "Key" : "cot:account", "Value" : "${accountId}" },
                                { "Key" : "cot:product", "Value" : "${productId}" },
                                { "Key" : "cot:segment", "Value" : "${segmentId}" },
                                { "Key" : "cot:environment", "Value" : "${environmentId}" },
                                { "Key" : "cot:category", "Value" : "${categoryId}" },
                                { "Key" : "cot:tier", "Value" : "${tierId}" },
                                { "Key" : "cot:component", "Value" : "${componentId}" },
                                { "Key" : "cot:zone", "Value" : "${zone.Id}" },
                                { "Key" : "Name", "Value" : "${formatComponentFullName(
                                                                tier,
                                                                component,
                                                                zone)}" }
                            ],
                            "UserData" : {
                                "Fn::Base64" : {
                                    "Fn::Join" : [
                                        "",
                                        [
                                            "#!/bin/bash -ex\n",
                                            "exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1\n",
                                            "yum install -y aws-cfn-bootstrap\n",
                                            "# Remainder of configuration via metadata\n",
                                            "/opt/aws/bin/cfn-init -v",
                                            "         --stack ", { "Ref" : "AWS::StackName" },
                                            "         --resource ${ec2InstanceId}",
                                            "         --region ${regionId} --configsets ec2\n"
                                        ]
                                    ]
                                }
                            }
                        },
                        "DependsOn" : [
                            "${ec2ENIId}"
                            [#if ec2.LoadBalanced]
                                ,"${ec2ELBId}"
                            [/#if]
                            [#if fixedIP]
                                ,"${ec2EIPAssociationId}"
                            [/#if]
                        ]
                    },
                    "${ec2ENIId}" : {
                        "Type" : "AWS::EC2::NetworkInterface",
                        "Properties" : {
                            "Description" : "eth0",
                            "SubnetId" : "${getKey(formatSubnetId(tier, zone))}",
                            "SourceDestCheck" : true,
                            "GroupSet" : [
                                {"Ref" : "${ec2SecurityGroupId}"}
                                [#if securityGroupNAT?has_content]
                                    , "${securityGroupNAT}"
                                [/#if]
                            ],
                            "Tags" : [
                                { "Key" : "cot:request", "Value" : "${requestReference}" },
                                { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                                { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                                { "Key" : "cot:account", "Value" : "${accountId}" },
                                { "Key" : "cot:product", "Value" : "${productId}" },
                                { "Key" : "cot:segment", "Value" : "${segmentId}" },
                                { "Key" : "cot:environment", "Value" : "${environmentId}" },
                                { "Key" : "cot:category", "Value" : "${categoryId}" },
                                { "Key" : "cot:tier", "Value" : "${tierId}" },
                                { "Key" : "cot:component", "Value" : "${componentId}" },
                                { "Key" : "cot:zone", "Value" : "${zone.Id}" },
                                { "Key" : "Name", "Value" : "${formatComponentFullName(
                                                                tier,
                                                                component,
                                                                zone,
                                                                "eth0")}" }
                            ]
                        }
                    }
                    [#if fixedIP]
                        ,"${ec2EIPId}": {
                            "DependsOn" : "${ec2ENIId}",
                            "Type" : "AWS::EC2::EIP",
                            "Properties" : {
                                "Domain" : "vpc"
                            }
                        }
                        ,"${ec2EIPAssociationId}": {
                            "DependsOn" : "${ec2EIPId}",
                            "Type" : "AWS::EC2::EIPAssociation",
                            "Properties" : {
                                "AllocationId" : { "Fn::GetAtt" : ["${ec2EIPId}", "AllocationId"] },
                                "NetworkInterfaceId" : { "Ref" : "${ec2ENIId}" }
                            }
                        }
                    [/#if]
                [/#if]
            [/#list]
            [#break]

        [#case "outputs"]
            [@outputsRef ec2RoleId /],
            [@outputsGetArnAtt ec2RoleId /]
            [#if fixedIP]
                [#list zones as zone]
                    [#if multiAZ || (zones[0].Id = zone.Id)]
                        [#assign ec2EIPId = formatComponentEIPId(
                                                tier,
                                                component,
                                                zone)]
                        [#-- Support backwards compatability with existing installs --] 
                        [#if !(getKey(ec2EIPId)?has_content)]
                            [#assign ec2EIPId = formatComponentEIPId(
                                                    tier,
                                                    component,
                                                    zone
                                                    "eth0")]
                        [/#if]

                        ,[@outputsIPAddress ec2EIPId /]
                        ,[@outputsAllocation ec2EIPId /]
                    [/#if]
                [/#list]
            [/#if]
            [#break]

    [/#switch]
    [#assign resourceCount += 1]
[/#if]