const { google } = require('googleapis');
const path = require('path');

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).send('Method Not Allowed');
  }

  try {
    const { action, spreadsheetId, range, valueInputOption, resource } = req.body;

    if (!spreadsheetId) {
      return res.status(400).json({ error: 'Spreadsheet ID is required' });
    }

    let auth;
    if (process.env.SERVICE_ACCOUNT_BASE64) {
      const decoded = Buffer.from(process.env.SERVICE_ACCOUNT_BASE64, 'base64').toString('utf-8');
      const credentials = JSON.parse(decoded);
      auth = new google.auth.GoogleAuth({
        credentials,
        scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      });
    } else if (process.env.SERVICE_ACCOUNT_JSON) {
      const credentials = JSON.parse(process.env.SERVICE_ACCOUNT_JSON);
      if (credentials.private_key) {
        credentials.private_key = credentials.private_key.replace(/\\n/g, '\n');
      }
      auth = new google.auth.GoogleAuth({
        credentials,
        scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      });
    } else {
      auth = new google.auth.GoogleAuth({
        keyFile: path.join(__dirname, '..', 'service_account.json'),
        scopes: ['https://www.googleapis.com/auth/spreadsheets'],
      });
    }

    const sheets = google.sheets({ version: 'v4', auth });

    if (action === 'get') {
      const response = await sheets.spreadsheets.values.get({ spreadsheetId, range });
      return res.json(response.data);
    } else if (action === 'update') {
      const response = await sheets.spreadsheets.values.update({
        spreadsheetId,
        range,
        valueInputOption: valueInputOption || 'USER_ENTERED',
        requestBody: resource,
      });
      return res.json(response.data);
    } else if (action === 'batchUpdate') {
      const response = await sheets.spreadsheets.values.batchUpdate({
        spreadsheetId,
        requestBody: resource,
      });
      return res.json(response.data);
    } else {
      return res.status(400).json({ error: 'Unknown action' });
    }
  } catch (error) {
    console.error('Sheets Proxy Error:', error);
    return res.status(500).json({ error: error.message });
  }
};
