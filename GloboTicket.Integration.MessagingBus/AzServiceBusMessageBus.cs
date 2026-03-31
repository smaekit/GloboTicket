using GloboTicket.Integration.Messages;
using Microsoft.Azure.ServiceBus;
using Microsoft.Azure.ServiceBus.Core;
using Microsoft.Extensions.Configuration;
using Newtonsoft.Json;
using System;
using System.Text;
using System.Threading.Tasks;

namespace GloboTicket.Integration.MessagingBus
{
    public class AzServiceBusMessageBus: IMessageBus
    {
        private readonly string connectionString;

        public AzServiceBusMessageBus(IConfiguration configuration)
        {
            connectionString = configuration.GetValue<string>("ServiceBusConnectionString");
        }

        public async Task PublishMessage(IntegrationBaseMessage message, string topicName)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
            {
                throw new InvalidOperationException("ServiceBusConnectionString is not configured.");
            }

            ISenderClient topicClient = new TopicClient(connectionString, topicName);

            var jsonMessage = JsonConvert.SerializeObject(message);
            var serviceBusMessage = new Message(Encoding.UTF8.GetBytes(jsonMessage))
            {
                CorrelationId = Guid.NewGuid().ToString()
            };

            await topicClient.SendAsync(serviceBusMessage);
            Console.WriteLine($"Sent message to {topicClient.Path}");
            await topicClient.CloseAsync();
        }
    }
}
