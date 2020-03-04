using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;

using Amazon.Lambda.Core;
using Amazon.Lambda.SQSEvents;
using Newtonsoft.Json.Linq;

using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using SlackMessageBuilder;
using static SlackMessageBuilder.Button;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.Json.JsonSerializer))]

namespace SlackJobPoster
{
    public class Function
    {
        private HttpClient client;
        private string webhook_url;
        public Function()
        {
            client = new HttpClient();
        }

        public async Task FunctionHandler(SQSEvent evnt, ILambdaContext context)
        {
            foreach (var message in evnt.Records)
            {
                await ProcessMessageAsync(message, context);
            }
        }

        private async Task ProcessMessageAsync(SQSEvent.SQSMessage message, ILambdaContext context)
        {
            SecretManager sm = new SecretManager();
            webhook_url = sm.Get("SLACK_WEBHOOK");

            JObject jobPost = JObject.Parse(message.Body);
            string jobPostHeader = jobPost.Value<string>("header");
            string jobPostUrl = jobPost.Value<string>("sourceId");
            string jobPostCustomer = jobPost.Value<string>("customer");

            JObject jsonObject = BuildSlackPayload(jobPostHeader, jobPostUrl, jobPostCustomer);

            await client.PostAsJsonAsync(webhook_url, jsonObject);

            await Task.CompletedTask;
        }

        public JObject BuildSlackPayload(string header, string sourceId, string jobPostCustomer = null)
        {
            Dictionary<string, Option> customers = GetListOfCustomers();

            BlocksBuilder builder = new BlocksBuilder();
            StaticSelect customerSelect = new StaticSelect("customer_select", customers.Values.ToList(), "Customer");
            SlackAction actions = new SlackAction("actions")
                            .AddElement(customerSelect);


            // check if we have detected a customer and if so set it as initial option
            if (!string.IsNullOrEmpty(jobPostCustomer))
            {
                actions.AddElement(new Button("addToClose_btn", "Add to Close", ButtonStyle.PRIMARY));
                if (customers.ContainsKey(jobPostCustomer))
                    customerSelect.AddInitialOption(customers[jobPostCustomer]);
            }

            // adding button in the proper place
            actions.AddElement(new Button("qualifyLead_btn", "Qualify Lead", string.IsNullOrEmpty(jobPostCustomer) ? ButtonStyle.PRIMARY : ButtonStyle.DEFAULT));

            builder.AddBlock(new Section(new Text(" ")));
            builder.AddBlock(new Section(new Text(" ")));
            builder.AddBlock(new Section(new Text("*" + header + "*" + Environment.NewLine + sourceId, "mrkdwn")));
            builder.AddBlock(actions);
            builder.AddBlock(new Divider());

            return builder.GetJObject();
        }

        private Dictionary<string, Option> GetListOfCustomers()
        {
            Dictionary<string, Option> customers = new Dictionary<string, Option>();
            customers.Add("DSB", new Option("DSB", "lead_q9WAvUeMbAj9zBsINtZgzxBTXfMwxixGyYmR9rk0ovP"));
            customers.Add("Efio", new Option("Efio", "lead_Xb8JdJdPYo7YfJ7oXro1E4IrcG983NLZYABhWTcSiOq"));

            return customers;
        }
    }
}