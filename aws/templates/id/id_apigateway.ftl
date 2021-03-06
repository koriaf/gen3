[#-- API Gateway --]

[#-- Resources --]

[#function formatAPIGatewayId tier component extensions...]
    [#return formatComponentResourceId(
                "api",
                tier,
                component,
                extensions)]
[/#function]

[#function formatAPIGatewayDeployId tier component extensions...]
    [#return formatComponentResourceId(
                "apiDeploy",
                tier,
                component,
                extensions)]
[/#function]

[#function formatAPIGatewayStageId tier component extensions...]
    [#return formatComponentResourceId(
                "apiStage",
                tier,
                component,
                extensions)]
[/#function]

[#function formatAPIGatewayLambdaPermissionId tier component link fn extensions...]
    [#return formatComponentResourceId(
                "apiLambdaPermission",
                tier,
                component,
                extensions,
                link,
                fn)]
[/#function]

[#-- Attributes --]

