using System.Collections.Generic;
using System.Linq;
using Newtonsoft.Json.Linq;
using SlackMessageBuilder;
using static SlackMessageBuilder.Button;

namespace SlackJobPosterReceiver
{
    public static class SlackHelper
    {
        public static string GetModal(string message_ts, string hookUrl)
        {
            //create Slack modal
            ModalBuilder builder = new ModalBuilder("Qualify Lead", message_ts).AddPrivateMetadata(hookUrl);
            builder.AddBlock(
                new Input(
                    new PlainTextInput("customer_name", "Customer name goes here")
                    , "Customer name"
                    , "Customer name as it will appear in Close", "customer_block"));

            return builder.GetJObject().ToString();
        }

        public static JObject BuildDefaultSlackPayload(string header, Option selectedOption, SlackPostState postState, string leadId = "")
        {
            Dictionary<string, Option> customers = GetListOfCustomers();

            BlocksBuilder builder = new BlocksBuilder();
            StaticSelect customerSelect = new StaticSelect("customer_select", customers.Values.ToList(), "Customer");
            SlackAction actions = new SlackAction("actions")
                            .AddElement(customerSelect);

            actions.AddElement(new Button("addToClose_btn", "Add to Close", ButtonStyle.PRIMARY));

            if (!(selectedOption is null))
                customerSelect.AddInitialOption(selectedOption);

            // adding button in the proper place
            actions.AddElement(new Button("qualifyLead_btn", "Qualify Lead"));

            builder.AddBlock(new Section(new Text(" ")));
            builder.AddBlock(new Section(new Text(" ")));
            builder.AddBlock(new Section(new Text(header, "mrkdwn")));

            if (postState == SlackPostState.ACTIONS)
                builder.AddBlock(actions);
            else if (postState == SlackPostState.FINAL)
                builder.AddBlock(new Section(new Text($":white_check_mark: *Opportunity added to <https://app.close.com/lead/{leadId}|Close.com>*", "mrkdwn")));

            builder.AddBlock(new Divider());

            return builder.GetJObject();
        }

        //get static list of cutomers
        private static Dictionary<string, Option> GetListOfCustomers()
        {
            Dictionary<string, Option> customers = new Dictionary<string, Option>
            {
                { "DSB", new Option("DSB", "lead_q9WAvUeMbAj9zBsINtZgzxBTXfMwxixGyYmR9rk0ovP") },
                { "Efio", new Option("Efio", "lead_Xb8JdJdPYo7YfJ7oXro1E4IrcG983NLZYABhWTcSiOq") }
            };

            return customers;
        }
    }
}