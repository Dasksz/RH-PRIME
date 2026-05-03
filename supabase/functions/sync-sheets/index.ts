import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { parse } from 'https://deno.land/std@0.168.0/encoding/csv.ts'

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface Employee {
  id: string;
  nome: string;
  cargo: string;
  unidade: string;
  admissao: string;
  avatar: string;
  epi: {
    status: string;
    ultimaEntrega: string | null;
    validade: string;
    link: string | null;
  };
  fardamento: {
    status: string;
    ultimaEntrega: string | null;
    validade: string;
    link: string | null;
  };
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // The Google Sheets URL provided
    const sheetUrl = 'https://docs.google.com/spreadsheets/d/123b1-UJTKMQWY7jdMmMPdPTpANMJSjw3/export?format=csv';
    
    console.log('Fetching Google Sheet...');
    const response = await fetch(sheetUrl);
    
    if (!response.ok) {
      throw new Error(`Failed to fetch sheet: ${response.status} ${response.statusText}`);
    }
    
    const csvData = await response.text();
    console.log('CSV Data fetched, length:', csvData.length);
    
    // Parse CSV
    const rows = parse(csvData, { skipFirstRow: false }) as string[][];
    
    if (!rows || rows.length === 0) {
      return new Response(JSON.stringify({ data: [] }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Skip the header row (index 0) and any potential empty rows
    const dataRows = rows.slice(1).filter(row => row && row[1] && row[1].trim() !== '');

    // Map rows to the expected employee format
    // Expected Columns based on checking:
    // 0: Admissão
    // 1: Nome Completo do Funcionário
    // 2: Função
    // 3: Data Última Entrega (EPI)
    // 4: Link Comprovante (EPI)
    // 5: Data Última Entrega (Fardamento)
    // 6: Link Comprovante (Fardamento)
    // 7: Check / Validação

    const employees: Employee[] = dataRows.map((row, index) => {
      // Helper to calculate status based on date
      const calculateStatus = (dateStr: string | undefined) => {
        if (!dateStr || dateStr.trim() === '') return 'pendente';
        
        // Try parsing DD/MM/YYYY or MM/DD/YYYY based on the sheet data
        // Assume MM/DD/YYYY based on previous python check output: '3/20/2025'
        const parts = dateStr.split('/');
        let dateObj: Date;
        
        if (parts.length === 3) {
            // Assuming format is MM/DD/YYYY from Google Sheets export
            dateObj = new Date(Number(parts[2]), Number(parts[0]) - 1, Number(parts[1]));
        } else {
            dateObj = new Date(dateStr);
        }

        if (isNaN(dateObj.getTime())) return 'pendente';

        const now = new Date();
        const diffTime = Math.abs(now.getTime() - dateObj.getTime());
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        
        // Simple logic: if less than 180 days, 'em_dia', else 'vencido'
        return diffDays < 180 ? 'em_dia' : 'vencido';
      };

      const name = row[1]?.trim() || '';
      
      // Generate initials for avatar
      const nameParts = name.split(' ');
      const initials = nameParts.length > 1 
        ? `${nameParts[0][0]}${nameParts[nameParts.length - 1][0]}`
        : (name.substring(0, 2) || '??');

      return {
        id: `emp_${index + 1}`,
        nome: name,
        cargo: row[2]?.trim() || 'Não especificado',
        unidade: 'Unidade Padrão', // Field missing in current extract, assigning default
        admissao: row[0]?.trim() || '',
        avatar: initials.toUpperCase(),
        epi: {
          status: calculateStatus(row[3]),
          ultimaEntrega: row[3]?.trim() || null,
          validade: '180 dias',
          link: row[4]?.trim() || null
        },
        fardamento: {
          status: calculateStatus(row[5]),
          ultimaEntrega: row[5]?.trim() || null,
          validade: '1 ano',
          link: row[6]?.trim() || null
        }
      };
    });

    console.log(`Parsed ${employees.length} employees`);

    return new Response(JSON.stringify({ data: employees }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error: any) {
    console.error('Error:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
}

// @ts-ignore: Deno is defined in Deno environment
if (typeof Deno !== 'undefined') {
  serve(handler)
}
