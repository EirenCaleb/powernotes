<?php
header('Content-Type: application/json');
echo json_encode(['ok' => true, 'message' => 'PowerNotes server is running', 'data' => null]);
