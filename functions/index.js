const functions = require('firebase-functions');
const { google } = require('googleapis');

exports.getServiceAccountEmail = functions.https.onRequest((req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  const email =
    (functions.config().app && functions.config().app.service_account_email) ||
    process.env.SERVICE_ACCOUNT_EMAIL ||
    '';

  if (!email) {
    res.status(500).json({
      error: 'Service account email is not configured.',
    });
    return;
  }

  res.json({
    serviceAccountEmail: email,
  });
});

exports.sheetsProxy = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  try {
    const { action, spreadsheetId, range, valueInputOption, resource } = req.body;

    if (!spreadsheetId) {
      res.status(400).json({ error: 'Spreadsheet ID is required' });
      return;
    }

    const auth = new google.auth.GoogleAuth({
      keyFile: './service_account.json',
      scopes: ['https://www.googleapis.com/auth/spreadsheets'],
    });

    const sheets = google.sheets({ version: 'v4', auth });

    if (action === 'get') {
      const response = await sheets.spreadsheets.values.get({ spreadsheetId, range });
      res.json(response.data);
    } else if (action === 'update') {
      const response = await sheets.spreadsheets.values.update({
        spreadsheetId,
        range,
        valueInputOption: valueInputOption || 'USER_ENTERED',
        requestBody: resource,
      });
      res.json(response.data);
    } else if (action === 'batchUpdate') {
      const response = await sheets.spreadsheets.values.batchUpdate({
        spreadsheetId,
        requestBody: resource,
      });
      res.json(response.data);
    } else {
      res.status(400).json({ error: 'Unknown action' });
    }
  } catch (error) {
    console.error('Sheets Proxy Error:', error);
    res.status(500).json({ error: error.message });
  }
});