[#-- Define VPC --]
[#if deploymentUnit?contains("vpc")]
    [#if resourceCount > 0],[/#if]
    [#switch segmentListMode]
        [#case "definition"]
            "vpc" : {
                "Type" : "AWS::EC2::VPC",
                "Properties" : {
                    "CidrBlock" : "${segmentObject.CIDR.Address}/${segmentObject.CIDR.Mask}",
                    "EnableDnsSupport" : ${(dnsSupport)?string("true","false")},
                    "EnableDnsHostnames" : ${(dnsHostnames)?string("true","false")},
                    "Tags" : [ 
                        { "Key" : "cot:request", "Value" : "${requestReference}" },
                        { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                        { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                        { "Key" : "cot:account", "Value" : "${accountId}" },
                        { "Key" : "cot:product", "Value" : "${productId}" },
                        { "Key" : "cot:segment", "Value" : "${segmentId}" },
                        { "Key" : "cot:environment", "Value" : "${environmentId}" },
                        { "Key" : "cot:category", "Value" : "${categoryId}" },
                        { "Key" : "Name", "Value" : "${productName}-${segmentName}" } 
                    ]
                }
            }
            
            [#-- Define Internet Gateway and connect it to the VPC --]
            [#if internetAccess]
                ,"igw" : {
                    "Type" : "AWS::EC2::InternetGateway",
                    "Properties" : {
                        "Tags" : [ 
                            { "Key" : "cot:request", "Value" : "${requestReference}" },
                            { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                            { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                            { "Key" : "cot:account", "Value" : "${accountId}" },
                            { "Key" : "cot:product", "Value" : "${productId}" },
                            { "Key" : "cot:segment", "Value" : "${segmentId}" },
                            { "Key" : "cot:environment", "Value" : "${environmentId}" },
                            { "Key" : "cot:category", "Value" : "${categoryId}" },
                            { "Key" : "Name", "Value" : "${formatName(productName, segmentName)}" }
                        ]
                    }
                },
                "${formatId("igw", "attachment")}" : {
                    "Type" : "AWS::EC2::VPCGatewayAttachment",
                    "Properties" : {
                        "InternetGatewayId" : { "Ref" : "igw" },
                        "VpcId" : { "Ref" : "vpc" }
                    }
                }
            [/#if]
            
            [#-- Define route tables --]
            [#assign solutionRouteTables = []]
            [#list tiers as tier]
                [#assign routeTableId = tier.RouteTable]
                [#assign routeTable = routeTables[routeTableId]]
                [#list zones as zone]
                    [#assign tableId = routeTableId + jumpServerPerAZ?string("X" + zone.Id,"")]
                    [#assign tableName = routeTable.Name + jumpServerPerAZ?string("-" + zone.Id,"")]
                    [#if !solutionRouteTables?seq_contains(tableId)]
                        [#assign solutionRouteTables = solutionRouteTables + [tableId]]
                        ,"${formatId("routeTable", tableId)}" : {
                            "Type" : "AWS::EC2::RouteTable",
                            "Properties" : {
                                "VpcId" : { "Ref" : "vpc" },
                                "Tags" : [ 
                                    { "Key" : "cot:request", "Value" : "${requestReference}" },
                                    { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                                    { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                                    { "Key" : "cot:account", "Value" : "${accountId}" },
                                    { "Key" : "cot:product", "Value" : "${productId}" },
                                    { "Key" : "cot:segment", "Value" : "${segmentId}" },
                                    { "Key" : "cot:environment", "Value" : "${environmentId}" },
                                    { "Key" : "cot:category", "Value" : "${categoryId}" },
                                    [#if jumpServerPerAZ]
                                        { "Key" : "cot:zone", "Value" : "${zone.Id}" },
                                    [/#if]
                                    { "Key" : "Name", "Value" : "${formatName(productName,segmentName,tableName)}" }
                                ]
                            }
                        }
                        [#list routeTable.Routes?values as route]
                            [#if route?is_hash]
                                ,"${formatId("route", tableId, route.Id)}" : {
                                    "Type" : "AWS::EC2::Route",
                                    "Properties" : {
                                        "RouteTableId" : { "Ref" : "${formatId("routeTable",tableId)}" },
                                        [#switch route.Type]
                                            [#case "gateway"]
                                                "DestinationCidrBlock" : "0.0.0.0/0",
                                                "GatewayId" : { "Ref" : "igw" }
                                                [#break]
                                        [/#switch]
                                    }
                                }
                            [/#if]
                        [/#list]
                    [/#if]
                [/#list]
            [/#list]
            
            [#-- Define network ACLs --]
            [#assign solutionNetworkACLs = []]
            [#list tiers as tier]
                [#assign networkACLId = tier.NetworkACL]
                [#assign networkACL = networkACLs[networkACLId]]
                [#if !solutionNetworkACLs?seq_contains(networkACLId)]
                    [#assign solutionNetworkACLs = solutionNetworkACLs + [networkACLId]]
                    ,"${formatId("networkACL", networkACLId)}" : {
                        "Type" : "AWS::EC2::NetworkAcl",
                        "Properties" : {
                            "VpcId" : { "Ref" : "vpc" },
                            "Tags" : [ 
                                { "Key" : "cot:request", "Value" : "${requestReference}" },
                                { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                                { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                                { "Key" : "cot:account", "Value" : "${accountId}" },
                                { "Key" : "cot:product", "Value" : "${productId}" },
                                { "Key" : "cot:segment", "Value" : "${segmentId}" },
                                { "Key" : "cot:environment", "Value" : "${environmentId}" },
                                { "Key" : "cot:category", "Value" : "${categoryId}" },
                                { "Key" : "Name", "Value" : "${formatName(productName, segmentName, networkACL.Name)}" }
                            ]
                        }
                    }                    
                    [#list ["Inbound", "Outbound"] as direction]
                        [#if networkACL.Rules[direction]??]
                            [#list networkACL.Rules[direction]?values as rule]
                                [#if rule?is_hash]
                                    ,"${formatId("rule", networkACLId,(direction="Outbound")?string("out", "in"), rule.Id)}" : {
                                        "Type" : "AWS::EC2::NetworkAclEntry",
                                        "Properties" : {
                                            "NetworkAclId" : { "Ref" : "${formatId("networkACL", networkACLId)}" },
                                            "Egress" : "${(direction="Outbound")?string("true","false")}",
                                            "RuleNumber" : "${rule.RuleNumber}",
                                            "RuleAction" : "${rule.Allow?string("allow","deny")}",
                                            "CidrBlock" : "${rule.CIDRBlock}",
                                            [#switch rule.Protocol]
                                                [#case "all"]
                                                    "Protocol" : "-1",
                                                    "PortRange" : { "From" : "${((rule.PortRange.From)!0)?c}", "To" : "${((rule.PortRange.To)!65535)?c}"}
                                                    [#break]
                                                [#case "icmp"]
                                                    "Protocol" : "1",
                                                    "Icmp" : {"Code" : "${((rule.ICMP.Code)!-1)?c}", "Type" : "${((rule.ICMP.Type)!-1)?c}"}
                                                    [#break]
                                                [#case "udp"]
                                                    "Protocol" : "17",
                                                    "PortRange" : { "From" : "${((rule.PortRange.From)!0)?c}", "To" : "${((rule.PortRange.To)!65535)?c}"}
                                                    [#break]
                                                [#case "tcp"]
                                                    "Protocol" : "6",
                                                    "PortRange" : { "From" : "${((rule.PortRange.From)!0)?c}", "To" : "${((rule.PortRange.To)!65535)?c}"}
                                                    [#break]
                                            [/#switch]
                                        }
                                    }
                                [/#if]
                            [/#list]
                        [/#if]
                    [/#list]
                [/#if]
            [/#list]

            [#-- Define subnets --]
            [#list tiers as tier]
                [#assign routeTableId = tier.RouteTable]
                [#assign routeTable = routeTables[routeTableId]]
                [#assign networkACLId = tier.NetworkACL]
                [#assign networkACL = networkACLs[networkACLId]]
                [#list zones as zone]
                    ,"${formatId("subnet", tier.Id, zone.Id)}" : {
                        "Type" : "AWS::EC2::Subnet",
                        "Properties" : {
                            "VpcId" : { "Ref" : "vpc" },
                            "AvailabilityZone" : "${zone.AWSZone}",
                            [#assign subnetAddress = addressOffset + (tier.Index * addressesPerTier) + (zone.Index * addressesPerZone)]
                            "CidrBlock" : "${baseAddress[0]}.${baseAddress[1]}.${(subnetAddress/256)?int}.${(subnetAddress%256)}/${subnetMask}",
                            "Tags" : [
                                { "Key" : "cot:request", "Value" : "${requestReference}" },
                                { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                                { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                                { "Key" : "cot:account", "Value" : "${accountId}" },
                                { "Key" : "cot:product", "Value" : "${productId}" },
                                { "Key" : "cot:segment", "Value" : "${segmentId}" },
                                { "Key" : "cot:environment", "Value" : "${environmentId}" },
                                { "Key" : "cot:category", "Value" : "${categoryId}" },
                                { "Key" : "cot:tier", "Value" : "${tier.Id}" },
                                { "Key" : "cot:zone", "Value" : "${zone.Id}" },
                                [#if routeTable.Private!false]
                                    { "Key" : "network", "Value" : "private" },
                                [/#if]
                                { "Key" : "Name", "Value" : "${formatName(productName, segmentName, tier.Name, zone.Name)}" }
                            ]
                        }
                    },
                    
                    "${formatId("routeTable", "association", tier.Id, zone.Id)}" : {
                        "Type" : "AWS::EC2::SubnetRouteTableAssociation",
                        "Properties" : {
                            "SubnetId" : { "Ref" : "${formatId("subnet", tier.Id, zone.Id)}" },
                            [#-- TODO: check the expression and simplify] --]
                            "RouteTableId" : { "Ref" : "${formatId("routeTable", routeTableId + jumpServerPerAZ?string("X" + zone.Id,""))}" }
                        }
                    },
                    
                    "${formatId("networkACL", "association", tier.Id, zone.Id)}" : {
                        "Type" : "AWS::EC2::SubnetNetworkAclAssociation",
                        "Properties" : {
                            "SubnetId" : { "Ref" : "${formatId("subnet", tier.Id, zone.Id)}" },
                            "NetworkAclId" : { "Ref" : "${formatId("networkACL", networkACLId)}" }
                        }
                    }
                [/#list]
            [/#list]
                        
            [#if jumpServer]
                [#assign tier = getTier("mgmt")]
                ,"${formatId("role", tier.Id, "nat")}": {
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
                                "PolicyName": "${formatName(tier.Id, "nat")}",
                                "PolicyDocument" : {
                                    "Version" : "2012-10-17",
                                    "Statement" : [
                                        {
                                            "Effect" : "Allow",
                                            "Action" : [
                                                "ec2:DescribeInstances",
                                                "ec2:ModifyInstanceAttribute",
                                                "ec2:DescribeSubnets",
                                                "ec2:DescribeRouteTables",
                                                "ec2:CreateRoute",
                                                "ec2:ReplaceRoute",
                                                "ec2:DescribeAddresses",
                                                "ec2:AssociateAddress"
                                            ],
                                            "Resource": "*"
                                        },
                                        {
                                            "Resource": [
                                                "arn:aws:s3:::${codeBucket}"
                                            ],
                                            "Action": [
                                                "s3:ListBucket"
                                            ],
                                            "Effect": "Allow"
                                        },
                                        {
                                            "Resource": [
                                                "arn:aws:s3:::${codeBucket}/*"
                                            ],
                                            "Action": [
                                                "s3:GetObject",
                                                "s3:ListObjects"
                                            ],
                                            "Effect": "Allow"
                                        }
                                    ]
                                }
                            }
                        ]
                    }
                },
                "${formatId("instanceProfile", tier.Id, "nat")}" : {
                    "Type" : "AWS::IAM::InstanceProfile",
                    "Properties" : {
                        "Path" : "/",
                        "Roles" : [ 
                            { "Ref" : "${formatId("role", tier.Id, "nat")}" }
                        ]
                    }
                },
                "${formatId("securityGroup", tier.Id, "nat")}" : {
                    "Type" : "AWS::EC2::SecurityGroup",
                    "Properties" : {
                        "GroupDescription": "Security Group for HA NAT instances",
                        "VpcId": { "Ref": "vpc" },
                        "Tags" : [
                            { "Key" : "cot:request", "Value" : "${requestReference}" },
                            { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                            { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                            { "Key" : "cot:account", "Value" : "${accountId}" },
                            { "Key" : "cot:product", "Value" : "${productId}" },
                            { "Key" : "cot:segment", "Value" : "${segmentId}" },
                            { "Key" : "cot:environment", "Value" : "${environmentId}" },
                            { "Key" : "cot:category", "Value" : "${categoryId}" },
                            { "Key" : "cot:tier", "Value" : "${tier.Id}"},
                            { "Key" : "cot:component", "Value" : "nat"},
                            { "Key" : "Name", "Value" : "${formatName(productName, segmentName, tier.Name, "nat")}" }
                        ],
                        "SecurityGroupIngress" : [
                            [#if (segmentObject.IPAddressBlocks)??]
                                [#list segmentObject.IPAddressBlocks?values as groupValue]
                                    [#if groupValue?is_hash]
                                        [#list groupValue?values as entryValue]
                                            [#if entryValue?is_hash && (entryValue.CIDR)?has_content ]
                                                [#if (!entryValue.Usage??) || entryValue.Usage?seq_contains("nat") ]
                                                    [#if (entryValue.CIDR)?is_sequence]
                                                        [#list entryValue.CIDR as CIDRBlock]
                                                            { "IpProtocol": "tcp", "FromPort": "22", "ToPort": "22", "CidrIp": "${CIDRBlock}" },
                                                        [/#list]
                                                    [#else]
                                                        { "IpProtocol": "tcp", "FromPort": "22", "ToPort": "22", "CidrIp": "${entryValue.CIDR}" },
                                                    [/#if]
                                                [/#if]
                                            [/#if]
                                        [/#list]
                                    [/#if]
                                [/#list]
                            [#else]
                                { "IpProtocol": "tcp", "FromPort": "22", "ToPort": "22", "CidrIp": "0.0.0.0/0" },
                            [/#if]
                            { "IpProtocol": "-1", "FromPort": "1", "ToPort": "65535", "CidrIp": "${segmentObject.CIDR.Address}/${segmentObject.CIDR.Mask}" }
                        ]
                    }
                },
                "${formatId("securityGroup",tier.Id, "all", "nat")}" : {
                    "Type" : "AWS::EC2::SecurityGroup",
                    "Properties" : {
                        "GroupDescription": "Security Group for access from NAT",
                        "VpcId": { "Ref": "vpc" },
                        "Tags" : [
                            { "Key" : "cot:request", "Value" : "${requestReference}" },
                            { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                            { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                            { "Key" : "cot:account", "Value" : "${accountId}" },
                            { "Key" : "cot:product", "Value" : "${productId}" },
                            { "Key" : "cot:segment", "Value" : "${segmentId}" },
                            { "Key" : "cot:environment", "Value" : "${environmentId}" },
                            { "Key" : "cot:category", "Value" : "${categoryId}" },
                            { "Key" : "cot:tier", "Value" : "all"},
                            { "Key" : "cot:component", "Value" : "nat"},
                            { "Key" : "Name", "Value" : "${formatName(productName, segmentName, "all", "nat")}"}
                        ],
                        "SecurityGroupIngress" : [
                            { "IpProtocol": "tcp", "FromPort": "22", "ToPort": "22", "SourceSecurityGroupId": { "Ref" : "${formatId("securityGroup", tier.Id, "nat")}" } }
                        ]
                    }
                }
                        
                [#list zones as zone]
                    [#if jumpServerPerAZ || (zones[0].Id == zone.Id)]
                        ,"${formatId("asg", tier.Id, "nat", zone.Id)}": {
                            "DependsOn" : [ "${formatId("subnet", tier.Id, zone.Id)}" ],
                            "Type": "AWS::AutoScaling::AutoScalingGroup",
                            "Metadata": {
                                "AWS::CloudFormation::Init": {
                                    "configSets" : {
                                        "nat" : ["dirs", "bootstrap", "nat"]
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
                                                            "echo \"cot:tier=${tier.Id}\"\n",
                                                            "echo \"cot:component=nat\"\n",
                                                            "echo \"cot:zone=${zone.Id}\"\n",
                                                            "echo \"cot:role=nat\"\n",
                                                            "echo \"cot:credentials=${credentialsBucket}\"\n",
                                                            "echo \"cot:code=${codeBucket}\"\n",
                                                            "echo \"cot:logs=${operationsBucket}\"\n",
                                                            "echo \"cot:backups=${dataBucket}\"\n"
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
                                                            "REGION=$(/etc/codeontap/facts.sh | grep cot:accountRegion | cut -d '=' -f 2)\n",
                                                            "CODE=$(/etc/codeontap/facts.sh | grep cot:code | cut -d '=' -f 2)\n",
                                                            "aws --region ${r"${REGION}"} s3 sync s3://${r"${CODE}"}/bootstrap/centos/ /opt/codeontap/bootstrap && chmod 0500 /opt/codeontap/bootstrap/*.sh\n"
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
                                        }
                                    },
                                    "nat": {
                                        "commands": {
                                            "01ExecuteRouteUpdateScript" : {
                                                "command" : "/opt/codeontap/bootstrap/nat.sh",
                                                "ignoreErrors" : "false"
                                            }
                                            [#if deploymentUnit?contains("eip")]
                                                ,"02ExecuteAllocateEIPScript" : {
                                                    "command" : "/opt/codeontap/bootstrap/eip.sh",
                                                    "env" : { 
                                                        [#-- Legacy code to support definition of eip and vpc in one template (deploymentUnit = "eipvpc" or "eips3vpc" depending on how S3 to be defined)  --]
                                                        "EIP_ALLOCID" : { "Fn::GetAtt" : ["${formatId("eip",tier.Id, "nat", zone.Id)}", "AllocationId"] }
                                                    },
                                                    "ignoreErrors" : "false"
                                                }
                                            [#else]
                                                [#if getKey("eip", tier.Id, "nat", zone.Id, "id")?has_content]
                                                    ,"02ExecuteAllocateEIPScript" : {
                                                        "command" : "/opt/codeontap/bootstrap/eip.sh",
                                                        "env" : { 
                                                            [#-- Normally assume eip defined in a separate template to the vpc --]
                                                            "EIP_ALLOCID" : "${getKey("eip", tier.Id, "nat", zone.Id, "id")}"
                                                        },
                                                        "ignoreErrors" : "false"
                                                    }
                                                [/#if]
                                            [/#if]
                                        }
                                    }
                                }
                            },
                            "Properties": {
                                "Cooldown" : "30",
                                "LaunchConfigurationName": {"Ref": "${formatId("launchConfig", tier.Id, "nat", zone.Id)}"},
                                "MinSize": "1",
                                "MaxSize": "1",
                                "VPCZoneIdentifier": [ 
                                    { "Ref" : "${formatId("subnet", tier.Id, zone.Id)}"}
                                ],
                                "Tags" : [
                                    { "Key" : "cot:request", "Value" : "${requestReference}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:configuration", "Value" : "${configurationReference}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:tenant", "Value" : "${tenantId}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:account", "Value" : "${accountId}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:product", "Value" : "${productId}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:segment", "Value" : "${segmentId}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:environment", "Value" : "${environmentId}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:category", "Value" : "${categoryId}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:tier", "Value" : "${tier.Id}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "cot:component", "Value" : "nat", "PropagateAtLaunch" : "True"},
                                    { "Key" : "cot:zone", "Value" : "${zone.Id}", "PropagateAtLaunch" : "True" },
                                    { "Key" : "Name", "Value" : "${formatName(productName, segmentName, tier.Name, "nat", zone.Name)}", "PropagateAtLaunch" : "True" }
                                ]
                            }
                        },
                    
                        [#assign component = { "Id" : ""}]
                        [#assign processorProfile = getProcessor(tier, component, "NAT")]
                        "${formatId("launchConfig", tier.Id, "nat", zone.Id)}": {
                            "Type": "AWS::AutoScaling::LaunchConfiguration",
                            "Properties": {
                                "KeyName": "${productName + sshPerSegment?string("-" + segmentName,"")}",
                                "ImageId": "${regionObject.AMIs.Centos.NAT}",
                                "InstanceType": "${processorProfile.Processor}",
                                "SecurityGroups" : [ { "Ref": "${formatId("securityGroup", tier.Id, "nat")}" } ],
                                "IamInstanceProfile" : { "Ref" : "${formatId("instanceProfile", tier.Id, "nat")}" },
                                "AssociatePublicIpAddress": true,
                                "UserData": {
                                    "Fn::Base64": { 
                                        "Fn::Join": [ 
                                            "", 
                                            [
                                                "#!/bin/bash -ex\n",
                                                "exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1\n",
                                                "yum install -y aws-cfn-bootstrap\n",
                                                "# Remainder of configuration via metadata\n",
                                                "/opt/aws/bin/cfn-init -v",
                                                "         --stack ", { "Ref" : "AWS::StackName" },
                                                "         --resource ${formatId("asg", tier.Id, "nat", zone.Id)}",
                                                "         --region ${regionId} --configsets nat\n"
                                            ]
                                        ]
                                    }
                                }
                            }
                        }
                    [/#if]
                [/#list]
            [/#if]
            [#break]

        [#case "outputs"]
            "${formatId("domain", "segment", "domain")}" : {
                "Value" : "${segmentDomain}"
            },
            "${formatId("domain", "segment", "qualifier")}" : {
                "Value" : "${segmentDomainQualifier}"
            },
            "${formatId("domain", "segment", "certificate")}" : {
                "Value" : "${segmentDomainCertificateId}"
            },
            "${formatId("vpc", "segment", "vpc")}" : {
                "Value" : { "Ref" : "vpc" }
            },
            "${formatId("igw", "segment", "igw")}" :
            {
                "Value" : { "Ref" : "igw" }
            }
            [#if jumpServer]
                [#assign tier = getTier("mgmt")]
                ,"${formatId("securityGroup", "mgmt", "nat")}" : {
                    "Value" : { "Ref" : "${formatId("securityGroup", tier.Id, "all", "nat")}" }
                }
            [/#if]
            [#list tiers as tier]
                [#list zones as zone]
                    ,"${formatId("subnet", tier.Id, zone.Id)}" : {
                        "Value" : { "Ref" : "${formatId("subnet", tier.Id, zone.Id)}" }
                    }
                [/#list]
            [/#list]
            [#break]

    [/#switch]
    [#assign resourceCount += 1]
[/#if]

