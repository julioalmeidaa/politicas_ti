#!/bin/bash

# Script para corrigir e finalizar a instalação
PROJECT_DIR="/var/www/policy-generator"

echo "Corrigindo arquivo JavaScript..."

# Completar o arquivo app.js
cat > $PROJECT_DIR/public/app.js << 'JSEOF'
let currentPolicyType = '';

const policies = {
    'uso-tecnologia': {
        title: 'Política de Uso de Tecnologia'
    },
    'mobilizacao': {
        title: 'Procedimento de Mobilização'
    },
    'desmobilizacao': {
        title: 'Procedimento de Desmobilização'
    },
    'seguranca': {
        title: 'Política de Segurança da Informação'
    }
};

function openModal(policyType) {
    currentPolicyType = policyType;
    const policy = policies[policyType];
    const modal = document.getElementById('policyModal');
    const title = document.getElementById('modalTitle');
    
    title.textContent = policy.title;
    modal.style.display = 'flex';
}

function closeModal() {
    document.getElementById('policyModal').style.display = 'none';
    document.getElementById('policyForm').reset();
}

function showNotification(message, type) {
    const notification = document.getElementById('notification');
    notification.textContent = message;
    notification.className = `notification ${type} show`;
    
    setTimeout(() => {
        notification.classList.remove('show');
    }, 3000);
}

async function saveToServer(policyData) {
    try {
        const response = await fetch('/api/save-policy', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                policyData,
                htmlContent: `<h1>${policyData.title}</h1><p>Empresa: ${policyData.companyName}</p>`
            })
        });
        
        const result = await response.json();
        return result;
    } catch (error) {
        throw new Error('Erro de conexão com o servidor: ' + error.message);
    }
}

document.getElementById('policyForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    
    const formData = {
        companyName: document.getElementById('companyName').value,
        sector: document.getElementById('sector').value,
        employees: document.getElementById('employees').value,
        title: policies[currentPolicyType].title,
        type: currentPolicyType
    };
    
    try {
        const result = await saveToServer(formData);
        
        if (result.success) {
            showNotification(result.message, 'success');
            setTimeout(() => {
                closeModal();
            }, 2000);
        } else {
            throw new Error(result.error);
        }
    } catch (error) {
        showNotification(error.message, 'error');
    }
});

window.addEventListener('click', function(e) {
    const modal = document.getElementById('policyModal');
    if (e.target === modal) {
        closeModal();
    }
});

document.querySelectorAll('.methodology-tab').forEach(tab => {
    tab.addEventListener('click', function() {
        const method = this.getAttribute('data-method');
        
        document.querySelectorAll('.methodology-tab').forEach(t => t.classList.remove('active'));
        this.classList.add('active');
        
        document.querySelectorAll('.policy-card').forEach(card => {
            if (method === 'all') {
                card.style.display = 'flex';
            } else {
                const methods = card.getAttribute('data-methods');
                if (methods && methods.includes(method)) {
                    card.style.display = 'flex';
                } else {
                    card.style.display = 'none';
                }
            }
        });
    });
});
JSEOF

# Instalar PM2 se não estiver instalado
if ! command -v pm2 &> /dev/null; then
    echo "Instalando PM2..."
    npm install -g pm2
fi

# Ir para o diretório do projeto
cd $PROJECT_DIR

# Parar processo PM2 se estiver rodando
pm2 delete policy-generator 2>/dev/null || true

# Iniciar aplicação com PM2
echo "Iniciando aplicação com PM2..."
pm2 start server.js --name policy-generator

# Configurar PM2 para iniciar com o sistema
pm2 startup
pm2 save

# Verificar se Nginx está instalado e configurado
if ! command -v nginx &> /dev/null; then
    echo "Instalando Nginx..."
    apt install -y nginx
fi

# Criar configuração do Nginx se não existir
if [ ! -f /etc/nginx/sites-available/policy-generator ]; then
    echo "Configurando Nginx..."
    cat > /etc/nginx/sites-available/policy-generator << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

    # Habilitar site
    ln -s /etc/nginx/sites-available/policy-generator /etc/nginx/sites-enabled/ 2>/dev/null || true
    
    # Remover site padrão se existir
    rm -f /etc/nginx/sites-enabled/default
fi

# Testar e reiniciar Nginx
nginx -t && systemctl restart nginx

# Configurar permissões
chown -R www-data:www-data $PROJECT_DIR
chmod -R 755 $PROJECT_DIR

echo ""
echo "=================================================="
echo "         INSTALAÇÃO CORRIGIDA E FINALIZADA"
echo "=================================================="
echo "URL de acesso: http://$(curl -s ifconfig.me 2>/dev/null || echo 'SEU-IP')"
echo "URL local: http://localhost"
echo "Porta interna: 3000"
echo ""
echo "Comandos úteis:"
echo "  - Status da aplicação: pm2 status"
echo "  - Logs da aplicação: pm2 logs policy-generator"
echo "  - Reiniciar aplicação: pm2 restart policy-generator"
echo "  - Status do Nginx: systemctl status nginx"
echo "=================================================="

# Testar se a aplicação está respondendo
sleep 3
if curl -s http://localhost:3000 > /dev/null 2>&1; then
    echo "✓ Aplicação está funcionando corretamente na porta 3000"
else
    echo "⚠ Verificar se a aplicação está rodando: pm2 status"
fi

if curl -s http://localhost > /dev/null 2>&1; then
    echo "✓ Nginx está funcionando corretamente na porta 80"
else
    echo "⚠ Verificar se o Nginx está rodando: systemctl status nginx"
fi
