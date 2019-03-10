#!/usr/bin/env php
<?php
/*
 * Copyright 2019 Luciano Iam <lucianito@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

$n = json_decode(file_get_contents($argv[1]));

$notification = [
   'notification' => [
      'title'  => $n->notification->title,
      'body'   => $n->notification->body,
      'icon'   => 'ic_notification',   // no tocar
      'sound'  => 'default'   // no tocar
   ],
   'data'   => [
      'url'          => $n->notification->url,
		'click_action' => 'FLUTTER_NOTIFICATION_CLICK' // no tocar
   ]
];

if (isset($n->registrationId)) {
   $notification['registration_ids'] = [$n->registrationId];
}
if (isset($n->topic)) {
   $notification['to'] = '/topics/' . $n->topic;
}

$headers = [
   'Authorization: key=' . $n->apiKey,
   'Content-Type: application/json'
];

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, 'https://fcm.googleapis.com/fcm/send');
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($notification));
$result = curl_exec($ch);
curl_close($ch);

echo $result;
echo "\n";
