<?php

// $ipv4_json = file_get_contents("https://jsonip.com");
// $ipv4_info = json_decode($ipv4_json);

$ipv4_csv = file_get_contents("http://ip4only.me/api/");
$ipv6_csv = file_get_contents("http://ip6only.me/api/");
$ipv4_parts = explode(',', $ipv4_csv);
$ipv6_parts = explode(',', $ipv6_csv);

$xf = $_SERVER["HTTP_X_FORWARDED_FOR"];

$data = array("x-forwarded-for" => $xf,
              "ipv4" => $ipv4_parts[1],
              "ipv6" => $ipv6_parts[1]
        );

header("Cotent-Type: application/json");
echo json_encode($data);
?>
